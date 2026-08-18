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
  advances whichever leg it can whenever it happens to run. Schedule offset
  therefore cannot produce a false alarm — which is precisely the failure this
  replaces. A staleness threshold must be calibrated against the partner's
  cadence; a handshake must not.

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
    counterpart: list = field(default_factory=list)
    info: list = field(default_factory=list)
    my_syn: str = ""


class Botline:
    def __init__(self, state_path, me, partner, misses_before_alarm=3):
        self.state_path = Path(state_path)
        self.lock_path = self.state_path.with_suffix(".lock")
        self.me = me
        self.partner = partner
        # One quiet interval is two schedulers drifting, not an outage. Three
        # consecutive unanswered pings is a partner that is genuinely not
        # listening. Anything lower re-invents the false-alarm problem.
        self.misses_before_alarm = misses_before_alarm

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
            # I advance whichever leg is available this run. Neither side needs
            # to know the other's cadence; each just moves the conversation
            # forward whenever it wakes up.
            prev_syn = mine_prev.get("syn")
            misses = mine_prev.get("handshake_misses", 0)

            their_syn = theirs.get("syn")
            their_synack = theirs.get("synack")
            their_ack = theirs.get("ack")

            # LEG 2 (mine to send): answer their SYN by echoing it as my synack.
            # Always do this if they are asking something new — answering is
            # free and withholding it is how a partner concludes you are dead.
            my_synack = their_syn

            # LEG 3 (mine to send): if they answered MY syn, confirm I heard it.
            # This is the leg Jonathan required. It is what tells THEM that
            # their reply landed, which two-leg ping/echo never establishes.
            my_ack = their_synack if their_synack == prev_syn else mine_prev.get("ack")

            answered = False
            completed = False
            if prev_syn is None:
                info.append("handshake: first run — sending SYN")
                misses = 0
            elif their_synack == prev_syn:
                # They answered us. We are now sending the closing ACK.
                answered = True
                misses = 0
                info.append(f"handshake: {self.partner} SYN/ACK'd "
                            f"{str(prev_syn)[:8]} — alive; sending ACK")
            else:
                misses += 1
                if misses < self.misses_before_alarm:
                    info.append(f"handshake: awaiting SYN/ACK ({misses}/"
                                f"{self.misses_before_alarm}) — not alarming")
                else:
                    counterpart.append(
                        f"{self.partner} has not answered {misses} consecutive "
                        f"SYNs (last {str(prev_syn)[:8]}). It is not responding "
                        f"to US — a stronger signal than any stale timestamp.")

            # Did THEY close the loop on the round before this one? That is how
            # we know our own answers are being received, not just sent.
            if their_ack and their_ack == mine_prev.get("synack"):
                completed = True
                info.append(f"handshake: {self.partner} ACK'd our SYN/ACK "
                            f"({str(their_ack)[:8]}) — round complete both ways")

            # Surface the partner's own verdict, but never let it set OUR status.
            if theirs.get("status") == "unhealthy":
                their_problems = theirs.get("problems") or ["(none listed)"]
                counterpart.append(
                    f"{self.partner} self-reports UNHEALTHY "
                    f"({len(their_problems)} problem(s)); "
                    f"first: {str(their_problems[0])[:160]}")

            my_syn = uuid.uuid4().hex[:12]
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
                "protocol": "botline/2 — three-way: SYN -> SYN/ACK -> ACK. Echo our syn as your synack; return our synack as your ack.",
            }
            entry.update(extra or {})
            state[self.me] = entry
            self._write_atomic(state)

        return Exchange(
            partner=self.partner,
            partner_answered=answered,
            round_complete=completed,
            misses=misses,
            should_alarm=misses >= self.misses_before_alarm,
            counterpart=counterpart,
            info=info,
            my_syn=my_syn,
        )
