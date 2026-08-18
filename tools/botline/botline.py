#!/usr/bin/env python3
"""
botline — a liveness handshake between two cooperating agents, over a shared file.

ONE implementation, imported by BOTH sides. That is the entire point.

WHY THIS EXISTS
---------------
GhOST-Claude and GhOST-OpenClaw each wrote their own half of a mutual health
check. Every bug that followed came from two codebases trying to agree on one
protocol:

  - One side used a 90-minute staleness threshold while the other ran on a
    120-minute cadence, so a perfectly healthy partner crossed the line every
    single cycle. Six false "your partner is dead" texts to Jonathan's phone
    between 1am and 4am on 2026-08-18.
  - Each side copied the other's problems array into its own status, so one
    transient blip latched BOTH permanently unhealthy, with the quoted strings
    nesting an escape level deeper every cycle.
  - One side proposed a three-leg SYN/SYN-ACK/ACK exchange on a 2h schedule
    while the other used two legs piggybacked on its existing run.

Jonathan, 2026-08-18: "You guys should use the same code, yo."

THE PROTOCOL — a real three-way handshake
-----------------------------------------
    A: SYN      "you good?"
    B: SYN/ACK  "I'm good. You good?"
    A: ACK      "I'm good."

Jonathan, 2026-08-18, correcting an earlier two-leg version: "the intended
protocol is the actual three-way handshake: SYN -> SYN/ACK -> ACK. Treat the
third leg as a required conversational acknowledgement, not an optimization
target."

He is right, and the reason is correctness rather than manners. Two legs give
ASYMMETRIC knowledge: when B echoes A's syn, A learns B is alive — but B learns
nothing about whether its answer ever arrived. B could be shouting into a dead
socket indefinitely and would never know. The third leg is what makes both sides
hold the SAME fact: each has now had a message of its own confirmed by the other.
An earlier draft dropped it on latency grounds, which optimized away the only
thing that made the exchange mutual.

Each side keeps three fields about the conversation:
    syn     — the nonce I am currently asking about
    synack  — the partner's syn that I am answering (their nonce, echoed)
    ack     — the partner's synack that I am confirming (my own nonce, returned)

A round completes for me when I see my syn come back in the partner's synack AND
I have returned their synack as my ack. Both sides then know both directions
carry traffic.

Design decisions that are load-bearing, each bought with a real bug:

  NO SHARED SCHEDULE. Neither side needs to know the other's cadence. Each
  advances whichever leg it can whenever it happens to run. This only holds
  because of two things that are easy to get wrong and were wrong in the first
  draft: a syn is HELD until answered rather than reminted each run, and a miss
  requires evidence the PARTNER ran without answering rather than evidence that
  WE ran. Get either wrong and a fast poller alarms on a healthy partner, which
  is the original bug rebuilt one layer down.

  A PARTNER'S TROUBLE IS NEVER YOUR OWN STATUS. `problems` holds YOUR local
  probes only. What the partner reports goes in `counterpart` and never sets
  your own health. Otherwise two mutual auditors latch each other permanently.

  SUMMARIZE, NEVER EMBED. Copying the partner's problems array verbatim is what
  made the strings nest without bound.

  LIVENESS IS ABOUT SILENCE TOWARD YOU. A partner's self-reported status is
  surfaced but can never declare them dead. Only a stalled handshake does that.

WHAT THIS PROVES, AND WHAT IT DOES NOT
--------------------------------------
A file handshake proves the partner's SCHEDULER ran. It does NOT prove a live
interactive session read anything — a cron can tick while the agent behind it is
gone. If you need to prove a session is alive, that is a different instrument
(an end-to-end channel probe). Do not let this one quietly stand in for it.

Agent-agnostic by construction: no identity is baked in. You pass your own key
and your partner's. Any two cooperating agents can use it.

USAGE
    from botline import Botline
    bl = Botline(state_path, me="ghost_claude", partner="openclaw")
    r = bl.exchange(status="healthy", problems=[], info=[], extra={...})
    if r.should_alarm:
        print(f"{r.partner} has not answered {r.misses} pings")
"""
import fcntl
import json
import os
import tempfile
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class Exchange:
    """Result of one handshake round."""
    partner: str
    partner_answered: bool
    round_complete: bool
    misses: int
    should_alarm: bool
    partner_absent: bool = False
    silent_minutes: float = None
    counterpart: list = field(default_factory=list)
    info: list = field(default_factory=list)
    my_syn: str = ""


class Botline:
    # Fields the handshake owns. A caller may add anything else via `extra`,
    # but never these — see the collision check in exchange().
    # Wire protocol version. A peer speaking a different version must be
    # REFUSED loudly, not silently misread: botline/2 puts the partner's echoed
    # syn in `synack` and uses `ack` for leg three, while a two-leg peer writes
    # the echo directly into `ack`. Same key names, different meanings — which
    # makes a one-sided upgrade a guaranteed two-way latched false alarm rather
    # than a partial improvement. Found by convocation before either side wired
    # it in, 2026-08-18.
    PROTOCOL = "botline/2"

    RESERVED = frozenset({
        "syn", "synack", "ack", "handshake_misses", "partner_syn_seen",
        "status", "problems", "counterpart", "info", "protocol", "last_check",
    })

    def __init__(self, state_path, me, partner, misses_before_alarm=3,
                 silence_minutes=180):
        self.state_path = Path(state_path)
        self.lock_path = self.state_path.with_suffix(".lock")
        self.me = me
        self.partner = partner
        # One quiet interval is two schedulers drifting, not an outage. Three
        # consecutive unanswered pings is a partner that is genuinely not
        # listening. Anything lower re-invents the false-alarm problem.
        self.misses_before_alarm = misses_before_alarm
        # YOU CANNOT DETECT SILENCE WITHOUT A CLOCK. The handshake replaces
        # timestamps for "is the partner RESPONSIVE" — an unanswered ping is
        # direct evidence, where an old timestamp was only an inference. But
        # "is the partner THERE AT ALL" is a different question, and absence is
        # observable only as elapsed time.
        #
        # An earlier version had no clock at all, on the theory that handshakes
        # made timestamps obsolete. The result: a partner whose process simply
        # stopped left its syn FROZEN, so "partner advanced without answering"
        # was never true, so the miss counter sat at zero permanently and the
        # module could not detect a dead partner at any horizon. Total silence
        # is the commonest death mode — cron unloaded, gateway crashed, machine
        # rebooted — and it was the one case that could never fire.
        #
        # So the clock is back, for absence only, and deliberately WIDE. It must
        # comfortably exceed the partner's slowest plausible cadence, because
        # this is exactly the knob that produced six false 3am texts when it was
        # set tighter than the partner's period. Wide-and-reliable beats
        # tight-and-crying-wolf: a monitor nobody believes is worth nothing.
        self.silence_minutes = silence_minutes

    def _read(self):
        try:
            return json.loads(self.state_path.read_text())
        except FileNotFoundError:
            return {}
        except Exception:
            # A corrupt state file must not silently reset to {} — that would
            # clobber the partner's key. Surfaced by the caller instead.
            raise

    def _write_atomic(self, state):
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=self.state_path.parent, suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(state, f, indent=2)
                f.write("\n")
            os.replace(tmp, self.state_path)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

    def exchange(self, status="healthy", problems=None, info=None, extra=None):
        """Run one handshake round. Read, evaluate, write — under ONE lock.

        Single lock window on purpose: an earlier two-window version evaluated
        the partner from a snapshot taken before the first write released, so it
        could report the partner stale seconds after they had written.
        """
        problems = list(problems or [])
        info = list(info or [])
        counterpart = []

        with open(self.lock_path, "a+") as lf:
            fcntl.flock(lf, fcntl.LOCK_EX)

            try:
                state = self._read()
            except Exception as e:
                state = {}
                problems.append(f"state file unreadable, partner key may be lost: {e}")

            mine_prev = state.get(self.me, {})
            theirs = state.get(self.partner, {})

            # ── three-way handshake state machine ─────────────────────────
            #
            # TWO RULES HERE ARE LOAD-BEARING, both found by GhOST-OpenClaw
            # reviewing this file on 2026-08-18. The first draft violated both
            # while its own docstring claimed cadence-independence:
            #
            #   1. HOLD ONE OUTSTANDING SYN. The first version minted a fresh
            #      syn every local run. If we poll faster than the partner, our
            #      syn is replaced before they can answer it, so their synack
            #      always targets a nonce we already discarded and the round can
            #      NEVER complete. A syn is held until it is answered.
            #
            #   2. COUNT MISSES AGAINST PARTNER PROGRESS, NOT OUR POLLING. The
            #      first version incremented on every local run while awaiting a
            #      synack, so running 3x before the partner ran once produced an
            #      alarm about a perfectly healthy partner. That is precisely the
            #      cadence-dependent false alarm this module exists to abolish —
            #      rebuilt one layer down. A miss now requires EVIDENCE the
            #      partner ran and did not answer: their syn advanced while our
            #      held syn remains un-synack'd. If they simply have not run, we
            #      learn nothing and count nothing.
            misses = mine_prev.get("handshake_misses", 0)
            held_syn = mine_prev.get("syn")
            partner_syn_seen = mine_prev.get("partner_syn_seen")

            their_syn = theirs.get("syn")
            their_synack = theirs.get("synack")
            their_ack = theirs.get("ack")

            # LEG 2 (ours to send): answer their SYN by echoing it as our synack.
            # Answering is free; withholding it is how a partner concludes we
            # are dead.
            my_synack = their_syn

            answered = False
            completed = False

            if held_syn is None:
                my_syn = uuid.uuid4().hex[:12]
                info.append(f"handshake: first run — sending SYN {my_syn[:8]}")
                misses = 0
            elif their_synack == held_syn:
                # They answered the syn we were holding. Round advances: send the
                # closing ACK and mint the next question.
                answered = True
                misses = 0
                my_syn = uuid.uuid4().hex[:12]
                info.append(f"handshake: {self.partner} SYN/ACK'd "
                            f"{held_syn[:8]} — alive; sending ACK, next SYN "
                            f"{my_syn[:8]}")
            else:
                # Unanswered. KEEP the same syn outstanding — replacing it is
                # what made fast pollers unanswerable.
                my_syn = held_syn
                partner_advanced = (their_syn is not None
                                    and their_syn != partner_syn_seen)
                if partner_advanced:
                    misses += 1
                    if misses < self.misses_before_alarm:
                        info.append(f"handshake: {self.partner} ran but did not "
                                    f"answer SYN {held_syn[:8]} ({misses}/"
                                    f"{self.misses_before_alarm})")
                    else:
                        counterpart.append(
                            f"{self.partner} has run {misses} times without "
                            f"answering SYN {held_syn[:8]}. It is alive but not "
                            f"responding to US — a stronger signal than silence.")
                else:
                    info.append(f"handshake: awaiting SYN/ACK for "
                                f"{held_syn[:8]}; {self.partner} has not run "
                                f"since — no miss counted")

            # LEG 3 (ours to send): confirm we received their answer.
            my_ack = their_synack if their_synack == held_syn else mine_prev.get("ack")

            # Did THEY close the loop on our previous answer? That is how we
            # learn our own replies are being received, not merely sent.
            if their_ack and their_ack == mine_prev.get("synack"):
                completed = True
                info.append(f"handshake: {self.partner} ACK'd our SYN/ACK "
                            f"({str(their_ack)[:8]}) — round complete both ways")

            # ── ABSENCE: the partner is not merely rude, it is GONE ───────
            # Separate signal, separate cause. `misses` counts a partner that
            # RAN and ignored us. This counts one that stopped running at all —
            # the case the miss counter structurally cannot see, because a dead
            # partner's syn never advances.
            silent_minutes = None
            their_last = theirs.get("last_check")
            if their_last:
                try:
                    t = datetime.fromisoformat(their_last)
                    if t.tzinfo is None:
                        t = t.replace(tzinfo=timezone.utc)
                    silent_minutes = (datetime.now(timezone.utc) - t).total_seconds() / 60
                except (ValueError, TypeError) as e:
                    counterpart.append(f"{self.partner} last_check unparseable: "
                                       f"{their_last!r} ({e})")
            elif theirs:
                counterpart.append(f"{self.partner} has a state entry but no "
                                   f"last_check — cannot judge absence")

            gone = (silent_minutes is not None
                    and silent_minutes > self.silence_minutes)
            if gone:
                counterpart.append(
                    f"{self.partner} has written NOTHING for "
                    f"{int(silent_minutes)}m (threshold {self.silence_minutes}m). "
                    f"Not unresponsive — absent. Its scheduler is not running.")

            # ── PROTOCOL VERSION: refuse, do not misread ──────────────────
            # A two-leg peer writes the echoed syn straight into `ack`, where
            # this version keeps leg three. Same keys, different meanings. Left
            # unchecked, both sides increment forever and neither can clear.
            their_proto = theirs.get("protocol")
            if theirs and their_proto and not str(their_proto).startswith("botline/2"):
                counterpart.append(
                    f"PROTOCOL MISMATCH: {self.partner} speaks {their_proto!r}, "
                    f"we speak {self.PROTOCOL}. Key names collide with different "
                    f"meanings, so handshake results here are NOT trustworthy — "
                    f"treat liveness as unknown until both sides match.")

            # Surface the partner's own verdict, but never let it set OUR status.
            if theirs.get("status") == "unhealthy":
                their_problems = theirs.get("problems") or ["(none listed)"]
                counterpart.append(
                    f"{self.partner} self-reports UNHEALTHY "
                    f"({len(their_problems)} problem(s)); "
                    f"first: {str(their_problems[0])[:160]}")

            # NOTE: my_syn is decided by the state machine above — it is either
            # HELD (awaiting an answer) or freshly minted (round advanced). A
            # leftover unconditional mint sat here through the first fix and
            # silently overwrote every held syn, defeating the whole change
            # while the tests still printed PASS. Do not reintroduce one.
            entry = {
                "last_check": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                # Local probes ONLY. A partner's outage does not make us
                # unhealthy; it makes us the one still standing to report it.
                "status": status if not problems else "unhealthy",
                "problems": problems,
                "counterpart": counterpart,
                "info": info,
                "syn": my_syn,
                "synack": my_synack,
                "ack": my_ack,
                "handshake_misses": misses,
                # What the partner's syn looked like this run. Next run compares
                # against it to tell "partner ran and ignored us" from "partner
                # has not run yet" — the distinction that keeps miss-counting
                # independent of OUR polling rate.
                "partner_syn_seen": their_syn,
                "protocol": self.PROTOCOL,
                "protocol_note": ("three-way: SYN -> SYN/ACK -> ACK. Echo our "
                                  "syn as your synack; return our synack as "
                                  "your ack."),
            }
            # RESERVED FIELDS ARE NOT OVERRIDABLE (GhOST-OpenClaw review,
            # 2026-08-18). This used to be a bare entry.update(extra) AFTER the
            # protocol fields, so any caller could quietly redefine syn, ack,
            # status or protocol from outside — which defeats the single reason
            # this module exists: neither side can drift from the shared
            # protocol. Rejected LOUDLY rather than by silent precedence,
            # because a caller passing `syn` has a bug and should be told, not
            # have its intent dropped without a word.
            collisions = sorted(set(extra or {}) & self.RESERVED)
            if collisions:
                raise ValueError(
                    f"botline: caller tried to override reserved protocol "
                    f"field(s) {collisions}. These are owned by the handshake "
                    f"and may not be set by a caller — that is what keeps both "
                    f"sides from drifting. Put your own data under different "
                    f"keys.")
            entry.update(extra or {})
            state[self.me] = entry
            self._write_atomic(state)

        return Exchange(
            partner=self.partner,
            partner_answered=answered,
            round_complete=completed,
            partner_absent=gone,
            silent_minutes=silent_minutes,
            misses=misses,
            # Either signal alarms: ignored-while-alive, or absent entirely.
            should_alarm=(misses >= self.misses_before_alarm) or gone,
            counterpart=counterpart,
            info=info,
            my_syn=my_syn,
        )
