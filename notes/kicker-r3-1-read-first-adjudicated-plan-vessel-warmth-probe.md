**Kicker R3 №1 — READ FIRST: adjudicated plan (vessel, warmth probe, race, tools, book)**

**Kicker R3 — R1 Fable (Claude)**

# fable\_r3 — the vessel, the race, the tools, the stake (Fable/Claude node, round 3, 2026-08-08)

Charter: BRIEF-R3.md under BRIEF.md + BRIEF-R2.md + all ten AMENDMENT-R2 points. sol\_r3.md not read

(independence rule; it did not exist at write time either). Everything cited below was re-opened this

round, not inherited: the five Keel receipts were re-verified against source at f049785b

(branch plan/comms-fabric), the matrix sections against docs/CLI-LIFECYCLE-CAPABILITY-MATRIX.md as it

sits on disk, and every tool note read in full from ~/.notesq/vault/md/iCloud-Notes/.

Receipts re-verified this round (so Lane-S claims below stand on source, not on the addenda):

| Claim | Where | Status |

|---|---|---|

| kickerd is the reporter delivery pump | KickerCore/Sources/kickerd/BusDelivery.swift:3 (&quotper-conductor message-bus delivery pump"), deliverConductorBus at :9 | confirmed |

| every supervision pass calls the pump | KickerCore/Sources/kickerd/ConductorNodeSupervision.swift:50 (`await deliverConductorBus(`) | confirmed |

| retry flood = retained cursor re-paste | KickerCore/Sources/kickerd/BusDeliverySupport.swift:97-98 (&quotretaining offset") | confirmed |

| the half-migration is documented as deliberate | KickerCore/Sources/kickerd/WatchdogPass.swift:27-34 (&quotThe two pipes are not merged; deleting the pump would stop every…") | confirmed |

| send reports ok:true on inbox routing, before any pane | KickerCore/Sources/KickerBackend/Executor/KickerWritesSend.swift:124-127 (`makeNoCorrespondenceChange(&quotsend", node, ok: true, … &quotrouted … to the inbox…")`) | confirmed |

| Sources LOC | KickerCore/Sources: 80,314 Swift lines; Tests: 86,343 | confirmed by count |

| busy/idle signatures are measured, non-enumerable | docs/CLI-LIFECYCLE-CAPABILITY-MATRIX.md:1483 (section head), :1632-1650 (glyph and verb both non-enumerable; elapsed-advancing is the only liveness proof) | confirmed |

| a built binary exists today | KickerCore/.build/debug/kicker, 53MB, mtime Aug 5 | confirmed |

| host reality | M4 Pro, 48GB RAM, macOS 26.5; claude 2.1.224, codex 0.147.0, qwen 0.20.1, agy installed; tart NOT installed yet | confirmed |

---

## A. The vessel — a Tart bed that cannot lie

### A0. Why this beats the hermitage (one paragraph, then mechanics)

The hermitage's two diseases were leakage (tmux corpses, orphaned daemons, state surviving between

runs on the shared host) and inertness (`tail -f /dev/null` roots, 25/37 scripts spawning no provider

at all — ADDENDUM-hermitage-census.md, ADDENDUM-keel-testimony.md item 6). A per-scenario disposable

macOS VM kills the first structurally: nothing survives `tart delete`, so a leak has nowhere to live

past its run. The second is killed by the catalog, not the VM: every pass condition in

SCENARIO-CATALOG-draft.md demands a provider-answered conversation observed from outside (S1's &quoteach

captured pane shows that provider's own live prompt," S18's nonce that no file carries). A fake root

cannot pass a single heat scenario. VM + catalog together are the &quotencoded in something better"

Jonathan asked for: green in this bed means a real crew did the real thing on a real macOS with a real

launchd and keychain, and then the world it happened in was destroyed and only evidence remained.

### A1. Golden image — build outline

Host: either MBP; commissioning on the M4 Pro (48GB), with the S23/overnight cell option on the M5 Max

(more RAM headroom; see A5). All tart specifics below that touch exact image names/flags get verified

at commissioning — tart is not installed yet, so this is a plan, not a transcript.

```

brew install cirruslabs/cli/tart

tart pull ghcr.io/cirruslabs/macos-tahoe-base:latest # or tart create --from-ipsw if no 26.x base is published

tart clone macos-tahoe-base kicker-golden

tart set kicker-golden --cpu 8 --memory 16384 --disk-size 100

```

In-guest provisioning (scripted over SSH; cirruslabs bases ship admin/admin with auto-login, which

matters — auto-login is what leaves the login keychain unlocked for headless work):

1. brew install tmux, git, python@3.13, node; npm/brew installs of claude (2.1.224), codex (0.147.0),

qwen (0.20.1), agy; herdr (for the audition, A6); pin every version.

2. Kill drift: `&quotenv": {&quotDISABLE\_AUTOUPDATER": &quot1"}` in the guest's ~/.claude/settings.json; no

auto-updating anything. Write /etc/kicker-vessel-manifest.txt: every CLI version, OS build, image

date. Every evidence manifest copies it (§A4) so any later failure is attributable to drift, not

mystery (PLAN-R2 §6's pinning rule, kept).

3. `sudo pmset -a sleep 0 displaysleep 0` — overnight scenarios must not lose to power management.

4. Install the in-guest runner: a dumb script that reads one scenario script from the mounted evidence

dir, executes it verbatim, exits. No opinions, no state.

5. mcp-aggregator wired IF any MCP cell survives the strike-pass (S27) — one stable PID approved once

during the auth hour, so no per-clone approval popups (the exact friction the Merge-MCP note names).

Then Jonathan's hour (A2), then seal: `tart stop`, `tart clone kicker-golden kicker-golden-20260810`.

Races reference dated, immutable snapshots only. The working golden is never run by a lane.

### A2. Auth-once-by-Jonathan — his hour, and the maintenance reality

The hour happens at the HOST's own screen with the VM window local, not over SSH — the

launch-locally lesson (TCC-gated things silently fail without Aqua pedigree) applies inside the guest

too: first-runs of each CLI, browser OAuth flows, and any TCC dialogs all want a real GUI session.

Sequence (estimate 45-60 min once):

1. Decide WHICH account set lives in the vessel — recommend the js/crew accounts, not his personal

ones, so vessel burn never collides with his interactive caps. (2 min decision, named here so it

doesn't become a mid-race surprise.)

2. `claude` login via guest Safari OAuth; one warm turn. Then `claude setup-token` and export

CLAUDE\_CODE\_OAUTH\_TOKEN in the guest shell profile — belt and suspenders, because Claude Code's

primary credential store on macOS is the login keychain, and keychain-under-SSH is the single most

likely headless failure (see prediction block; the env-token path bypasses it cleanly).

3. `codex` login (writes ~/.codex/auth.json — plain file, travels with the image). One warm turn.

4. `qwen` login (~/.qwen oauth file — same). One warm turn. 5. agy login; agy stays best-effort per

the catalog (S3's rule) — if its auth is exotic, it does not block commissioning.

6. Approve every TCC/automation dialog that appears, once, forever (they bake into the image).

Maintenance reality, stated without optimism: clones refresh access tokens independently against the

same stored refresh credentials. His own fleet already proves concurrent same-account sessions are

tolerated (multiple claude nodes under one account is kicker's daily reality), but refresh-token

ROTATION under clone concurrency is the vessel's biggest unknown. Three mitigations, priced:

- Canary at every clone boot: one scripted warm one-shot per brand (`claude -p &quotsay pong"`, codex/qwen

equivalents). Canary failure = vessel fault: neither lane billed, both clocks pause. This converts

silent auth decay into a named, non-attributable event.

- Monthly golden-refresh: boot the WORKING golden itself (not a clone), one warm turn per CLI so it

re-seals fresh tokens, stop, re-date the snapshot. Zero Jonathan-minutes when it refreshes headlessly;

10-15 min/month worst case if a provider demands interactive re-auth.

- If rotation proves strict (clone A's refresh invalidates the stored token for clone B), the fallback

is already staged: the setup-token env path for claude, auth.json refreshed only by the golden for

codex/qwen, clones kept short-lived so they never need to refresh at all. Clone TTL ≤ 24h (A7 #7)

makes this the default posture anyway.

### A3. Clone → run → harvest → destroy — the cycle and its cost

```

tart clone kicker-golden-20260810 lane-p-S17-20260812T0930 # APFS CoW: seconds, ~KB until writes

tart run lane-p-S17-… --no-graphics --dir=evidence:~/kicker-race/evidence/lane-p/S17/&ltrun-id>

# boot to SSH-able: ~25-45s (tart ip &ltclone> → ssh admin@…)

# canary: ~1-2 min (three provider round-trips)

# scenario runs (minutes to overnight, scenario-dependent)

# harvest: evidence was written host-side the whole time via the mount — nothing to copy

tart delete lane-p-S17-… # seconds; the world ends

```

Overhead ≈ 3 minutes per run beyond scenario runtime; disk high-water a few GB per live clone (CoW —

the same APFS mechanism THE-GOAL.md:141-142 pins for packages, which is a pleasing symmetry: the

vessel clones the way the product clones). Throughput is bounded not by clone cost but by the 2-VM

limit (A5). The runner drives scenarios over SSH; captures (`tmux capture-pane -p`), process lists

(`ps axo pid,command` + `grep -F`), and file reads are taken by the HARNESS's own SSH session with

absolute paths — the evidence-collection path is not something a lane can shadow (B5 #7).

### A4. Evidence contract — artifacts outlive the VM, open-able by human hands

```

~/kicker-race/evidence/&ltlane>/&ltscenario>/&ltrun-id>/

manifest.json scenario id · lane · clone name · golden snapshot id · guest manifest copy

(CLI versions, OS build) · daemon cell · start/stop UTC · exit status · shasums

commands.txt every command the harness injected, verbatim, in order

captures/ timestamped pane captures (plain text)

ps/ timestamped process listings (plain text)

package/ post-run copy of crew.kicker — node.json token diffs are read HERE, not asserted

transcript-L.md the driving LLM's transcript, for L-cells

verdict/ harness pass/fail + critic reviews — appended by critics, never by lanes

```

Rules: harness-owned, append-only, write-once per run-id; shasums recorded in the manifest at write

time so tampering is detectable; everything plain text so Jonathan can `open` or `grep -F` any of it

with no tool between him and the record. Lanes never write here. No limits, windows, or truncation

anywhere in the evidence path — captures are full-pane with full scrollback (`-S -`), ps listings are

complete; the one justified bound is clone TTL, and it is justified in A7 #7.

### A5. The 2-concurrent-macOS-VM constraint, mapped

Apple's Virtualization.framework allows two concurrent macOS guests per host. The mapping writes

itself: \*\*slot 1 = Lane S's clone, slot 2 = Lane P's clone\*\*, one live clone per lane at a time,

scenarios serial within a lane (which the one-at-a-time authoring rule wants anyway — AMENDMENT-R2

point 3). Verification replays and critic re-runs queue behind the lanes on the M4 Pro, or run on the

M5 Max as a second vessel host carrying its own copy of the dated golden (plain file copy of

~/.tart/vms or a private OCI push — decided at commissioning). The S23 overnight bake-off cell (five

ensembles, 15+ provider processes in ONE guest) gets `tart set --memory 24576`+ and prefers the M5

Max. RAM math on the M4 Pro: 2×16GB guests + host ≈ fine at 48GB; the bake-off cell is the one that

wants the bigger machine.

Cross-platform note, per the charter (annotate, don't solve): the same catalog re-runs later in

Tart-Linux or Docker vessels with no design change — only launchd/keychain cells (OP-0 mode

assertions, kickerd-present cells, S26's launchd candidate) are macOS-bound. Annotated; not built.

### A6. The substrate inside the VM — tmux default, Herdr auditioned on day one

The guest carries BOTH tmux and Herdr. tmux is the incumbent substrate (Lane S's Swift is tmux-native;

the catalog's observable-pass language is tmux-phrased). The Herdr audition is the vessel's day-one

spike, per the standing ruling (PLAN-R2 §8), sharpened to the brief's four questions:

\*\*Audition design (one day, in a clone, scripted):\*\*

1. Launch claude + codex + qwen under Herdr. Drive ~20 state transitions per brand: idle→busy (long

task), busy→idle (completion), blocked (a real permission prompt — claude's tool-approval stop is a

genuine &quotblocked" state tmux cannot name), exit.

2. Ground truth runs in parallel: timestamped pane/output reads every 2s plus the matrix's

elapsed-advancing discipline (docs/CLI-LIFECYCLE-CAPABILITY-MATRIX.md:1632 — the only proven

liveness signal). Every transition gets a row: (t, herdr\_claim, watched\_truth).

3. The brief's four questions, answered by measurement, not by its comparison page:

- \*\*Real state events vs pane-divination?\*\* Read its socket API in the running clone: if `wait`

blocks on a state CHANGE (push), that is event-shaped; if we must poll `read`, it is divination

with better packaging. Its own docs say detection is process-name matching + output heuristics —

that IS divination; the audition grades whether its heuristics beat our measured matrix, which is

the only question that matters.

- \*\*Dumb on-disk transcripts?\*\* Kill herdr; the conversation record must remain as plain files a

human opens without herdr running. If the record is opaque or dies with the daemon, fail — that

is a third opinion about history, the disease we just excised.

- \*\*Headless clone-cycling?\*\* The whole audition runs over SSH in a clone with no GUI. If herdr

needs a display or phones home (telemetry = hermeticity breach), fail immediately.

- \*\*All three CLIs?\*\* The 20-transition table per brand, including agy as a bonus row if time

allows. Its advertised roster covers the brands; advertised is not measured.

4. Pre-registered pass bars: zero false idle/done while a provider is demonstrably mid-turn (the

dangerous lie — a false &quotdone" is exactly the hallucinated-doneness disease); transition lag ≤5s in

≥90% of rows; socket `send` lands a nonce with S2 fidelity; transcripts pass the kill-test; fully

headless. Miss any bar → tmux stays, Herdr re-parked with the measured table as the reason.

5. Outcome wiring: win → Lane P MAY adopt herdr as substrate, and the harness observation adapter

(~50 lines, list/capture/send, plain string parsing, no regex) grows a herdr backend beside its

tmux backend. Lane S stays tmux regardless — re-substrating 80k lines of tmux-native Swift is a

rewrite by definition and outside Lane S's boundary (B6). The asymmetry is pre-registered as NOT

rigging: substrate is each lane's own engineering freedom; pass conditions are substrate-neutral

observations (B2).

### A7. Falsifying my own vessel — leaks that COULD survive it

1. \*\*Provider-side shared state.\*\* All clones burn one account's caps. A runaway lane starves the

other — cross-lane contamination through Anthropic's meter, invisible to the VM boundary.

Mitigation: per-lane daily token budgets in the ledger, CodexBar on the host, heavy cells scheduled

into cap-refresh windows. Not structural; named and watched.

2. \*\*Auth rotation races\*\* (A2). Two clones refreshing the same stored refresh token can invalidate

each other server-side. The canary catches it; the TTL posture minimizes it; it remains the

likeliest vessel breakage (I stake on it in D).

3. \*\*The host is not inside the vessel.\*\* The race harness, the lanes' own bot sessions, and the

evidence store live on the host — tmux corpses can still leak THERE. The vessel protects scenario

truth, not host hygiene. Mitigation: the harness is a dumb script set, not a daemon; lanes' own

dev sessions are their business, but evidence only ever comes from inside clones.

4. \*\*Evidence-dir contamination.\*\* The mounted dir is the one thing that persists; a scenario writing

state a later run reads would resurrect cross-run leakage through the vessel's own porthole.

Write-once per run-id + manifest shasums + critics checking mtimes.

5. \*\*Golden-seeded provider conversations.\*\* Clones share the golden's ~/.claude session files;

concurrent clones resuming the same provider conversation mutate shared server-side history. For

warmth scenarios that is realism (it IS the cp -R collision), but across RUNS it is contamination:

run N+1's &quotwarm" answer could be warmed by run N. Discipline: fresh NONCE per run (the catalog

already requires it), and warmth scenarios seed their nonce inside the run, never in the golden.

6. \*\*Version drift by self-update\*\* — killed in A1 #2, but only if the disable actually holds for

every brand; the manifest diff at harvest catches an escape (manifest.json vs guest reality).

7. \*\*The long-lived debugging clone.\*\* A lane keeping a clone alive for days to poke at failures has

rebuilt the hermitage inside the vessel. Rule: clone TTL 24h, harness-enforced (`tart list` sweep;

the only exception is a named overnight scenario cell, which is a scenario, not a debug session).

Justification for this bound, per the no-unjustified-limits rule: the TTL exists to make leaked

worlds structurally short-lived; overnight cells are exempted by name.

8. \*\*What the vessel cannot prove at all:\*\* anything about HIS machine — TCC on his real host, his

real ensemble.kicker's 1.8GB of residue, his muscle-memory workflows. The vessel proves the

product; the cutover onto his Mac stays a separate, quorum-gated event (CLAUDE.md: install needs

3-of-4 named bots), with S14/S2's convert-at-rest cells as the bridge.

---

## B. The race protocol — pre-registered, before any lane starts

### B1. The two lanes and the finish line

- \*\*Lane S:\*\* fix the EXISTING Swift (from f049785b, branch `race/lane-s`) until the heat greens in

the vessel. - \*\*Lane P:\*\* implement the Python core (fresh repo, `race/lane-p`) until the SAME heat

greens in the SAME vessel, from the same dated golden.

\*\*The heat (proposed subset — drawn from SCENARIO-CATALOG-draft.md, binding only AFTER Jonathan's

strike-pass; whatever survives his strike replaces this list 1:1):\*\*

| # | Catalog | Why it is in the heat |

|---|---|---|

| 1 | S1 | first light — crew visibly alive, per-brand panes |

| 2 | S2 | send lands, idle target (claude/codex/qwen cells) |

| 3 | S3 | send vs busy — one brand (claude) as the representative cell |

| 4 | S4 | the send that must never lie (KickerWritesSend.swift:124-127 is the standing counterexample) |

| 5 | S5 | Keel's proof — kill kickerd, messaging continues / structural daemonlessness |

| 6 | S6 | attach + converse + idle pane stays byte-identical |

| 7 | S8 | stop the world, relaunch warm |

| 8 | S11 | one command ends the tree, zero orphans at 0s and 60s |

| 9 | S12 | wrong cwd refuses loudly by name (THE-GOAL.md:100-113's second hard part) |

| 10 | S16 | cold cp -R launches untouched |

| 11 | S17 | live clone — every colliding token forks, nothing refuses (THE-GOAL.md:9-11) |

| 12 | S18 | the copy answers WARM (THE-GOAL.md:12) |

| 13 | S20 | cold-copy negative control — zero forks (fork-always is as wrong as fork-never) |

| 14 | S29 | &quotunknown" when unreadable — the product-level no-guessing rule |

S23 (the full overnight bake-off) is the championship VERIFICATION, run once by the first lane to

claim the heat: it is THE-GOAL's stop condition, too long to iterate inside a race clock, and its

bookend minutes are identical for both lanes so it moves no needle — but no verdict publishes without

it. S24-S27 (bots-driving-bots, LLM operator path) stay in the catalog as post-race build-out under

the one-at-a-time rule; putting full autonomy cells inside a two-week race would make the race about

prompt engineering, not about the hull. If Jonathan strikes differently, his strike governs.

### B2. &quotGreen," defined; who verifies

A scenario is green for a lane when, in a fresh clone from the dated golden:

1. The H-cell passes: the harness replays the scenario's ACTIONS verbatim over SSH; every OBSERVABLE

PASS condition in the catalog is met in harness-collected evidence (captures, ps, package diffs) —

never in the system's own claims about itself. Daemon column honored: `both` cells run twice on

Lane S's binary; Lane P's hull has only the daemonless cell, and S5's pass there is structural

(`ps` clean of any daemon for the whole run).

2. The L-cell (where the catalog defines one) passes: a fresh LLM, not part of either lane, drives via

`--json`; transcript saved; the same outside checks pass at each stage.

3. Substrate-neutral phrasing: pass conditions read &quotthe substrate's session list / a pane capture via

the substrate" — collected through the harness's twin-backend adapter (A6 #5) so a herdr-based

Lane P and a tmux-based Lane S face identical observation.

4. Cross-model check: GLM-5.2 and DeepSeek (qwen CLI, the study's standing critics) each review the

evidence bundle and concur the effect is shown BY the evidence. Disagreement = not green; resolved

by re-run, never by argument.

5. Jonathan spot-audit at claimed finish: he picks any 2 of the 14, watches the replay or reads the

bundle, ~15 min each. His veto outranks everything.

\*\*Finish line: all 14 scenarios green per the above, then S23 verifies.\*\* First lane there, by the

primary clock, wins.

### B3. The clock — Jonathan-attention-minutes primary, wall-clock secondary

The ledger (append-only, public to both lanes) bills to a lane: direct questions to Jonathan, rulings

requested, spot-audits CAUSED by that lane's ambiguous evidence, and any breakage of his live systems

attributable to the lane. Minutes measured from convoq timestamps (ask → his answer), rounded up.

Billed to NEITHER lane (vessel/fixed overhead): golden build + his auth hour, the strike-pass, canary

failures, VM/host faults, the end-of-race spot-audits, S23 bookends. Both wall-clocks PAUSE during

vessel outages. The comparison at the end is \*\*J-minutes at each lane's own green\*\* — not calendar

position (see B8 splits). Wall-clock (calendar time from race start to green) is the secondary metric

and tiebreak within ±10 J-minutes.

### B4. Timebox and abort

- \*\*14 calendar days\*\* from race start (race start = strike-pass done + vessel commissioned + both

lanes' worktrees frozen at their starting commits).

- A lane with zero greens by day 5 gets one diagnosis day; zero greens by day 7 = lane halts and

writes up (clean failure is information — BRIEF.md's own rule; no shame clause needed).

- Vessel down &gt2 cumulative days = race suspended, vessel redesigned before clocks resume.

- Cap exhaustion twice in one lane = that lane's heavy cells move to overnight windows; three times =

the lane's schedule is the problem and its wall-clock keeps running (budgeting is part of the craft).

- Jonathan may stop anything at any time; his stop-minutes bill to neither lane.

### B5. Anti-rigging

1. \*\*Isolation:\*\* separate repos/worktrees, separate branches, no shared scratch; each lane's diffs

embargoed from the other until both finish or the timebox ends.

2. \*\*Untouchables:\*\* neither lane may modify the golden image, the harness, the scenario definitions,

or the evidence store. Scenario-text changes only via Jonathan (they are his words by

construction — every scenario carries a HIS WORDS citation).

3. \*\*Anti-sweep commit guard (Lane S):\*\* every commit names the scenario it serves and keeps

`swift build` green; the guard (plain string checks, no regex) flags any commit that adds &gt500 new

lines with no scenario linkage for critic review. Subtraction rules apply: deletion is always in

bounds; stealth-rewrite is what the guard exists to surface, backstopped by the Theseus audit (B6).

4. \*\*Symmetry of means:\*\* identical clone budgets, identical per-day token budgets, one golden for

both, one harness for both, same critics for both.

5. \*\*Evidence integrity:\*\* harness-owned append-only store, manifest shasums (A4); critics check

bundle mtimes against manifest stamps.

6. \*\*Observation is lane-untouchable:\*\* all verification commands issue from the harness's own SSH

session with absolute paths; nothing sourced from a lane-writable environment. A lane shipping

shims that shadow `tmux`/`ps` inside its package cwd changes nothing the harness sees.

7. \*\*No self-verification:\*\* a lane's own green claim triggers a harness re-run in a FRESH clone; only

the harness run counts.

### B6. What Lane S may touch — fixing ≠ rewriting in place

- Start: f049785b. Day one is the DELETE-ALL order (AMENDMENT-R2 point 3): KickerCore/Tests (86,343

LOC), the hermitage/ghost-house/release-acceptance apparatus (scripts/hermitage-regression-tests/,

38 files), every unit test. Deletion anywhere is always allowed — subtraction IS the fix, and the

cut map is already named: BusDelivery.swift, the ConductorNodeSupervision.swift:50 call, the

BusDeliverySupport.swift:97 cursor/retry machinery, the WatchdogPass.swift:27-34 &quotnot merged"

dependency — Keel's excision, completed by deletion, not pump repair (&quotDo not restart kickerd merely

to restore the old pump," ADDENDUM-keel-testimony.md:33-37; &quotNO communication code whatsoever in

kickerd" — Jonathan).

- Modification of existing files: unrestricted. New Swift: allowed, but the race diff's total ADDED

Swift is capped at \*\*8,000 lines\*\*. Rationale, stated so the number is not arbitrary: the six

operator verbs close over 60,178 of 80,314 Sources LOC (R2 cross-exam measurement) — if &quotfixing"

needs more than ~10% of the closure in NEW code, the codebase is not being fixed, it is being

replaced; and 8k ≈ the entire expected size of Lane P's core, so the cap keeps the two lanes'

meanings distinct.

- Must keep: the `kicker` CLI verbs and JSON surface as the operator interface; package-format

compatibility (the at-rest converter path, THE-GOAL.md:126-134, stays real); tmux as substrate.

- \*\*Theseus audit at finish, pre-registered:\*\* if &gt40% of the surviving non-test LOC in the shipped

result is race-authored, the outcome is recorded as &quotrewrite in Swift clothes" — which is NOT the

&quotexisting Swift can be fixed" Jonathan defined as Python's defeat condition, and the book says so.

Ruled now so nobody argues it at the finish.

- Amendment 8 rider: any Swift-retaining verdict owes the SPM→Xcode migration (real targets, real

dependency graph, no umbrella, &quotno bullshit") BEFORE install — outside the race clock, priced 2-4

Jonathan-hours in the book, never deferred.

### B7. What Lane P may touch

- Fresh repo. May vendor convoq/session-bridge (the ecosystem's only Python with a working record —

BRIEF-R3 prior 3). May read everything, including the Swift (measured knowledge transfers as docs —

amendment 5; a ban on reading would be unenforceable theater, and transliteration can't game

scenarios the Swift itself has never passed). May NOT read Lane S's race diffs.

- No daemon, ever — S5's pass is structural. Python 3.13, stdlib-first; dependency list pre-registered

in the book at race start (a ballooning dep list is a falsifier of the &quotsimple core" thesis). No

regex anywhere (charter rule 4); tmux driven by plain subprocess with plain-string parsing, or herdr

via its socket if the audition passed.

- The four substrate-subprocess proofs from PLAN-R2 §2 Act 2 (stale reads, option races, atomic

paste+submit, socket bind) are INSIDE Lane P's first-week scope, not assumed — they are what S2/S3's

cells will fail on if skipped.

### B8. Outcomes, including splits — pre-registered

| Outcome | Ruling |

|---|---|

| P greens the heat + S23 first, fewer J-min | Swift dies in the fire (his words, amendment 5). No SPM→Xcode ever. Cutover install remains the 3-of-4 named-bot quorum's call — race victory is not install. |

| S greens first, fewer J-min, Theseus audit passes | &quotPython loses. For now." (his words — the &quotfor now" is part of the ruling). Amendment-8 migration owed before install. Lane P's spike learnings archived in the book. |

| S greens first on wall-clock, P's green consumed fewer J-min | \*\*Primary metric rules: P wins.\*\* J-minutes was declared the clock before the race; wall-clock is tiebreak only within ±10 J-min. |

| S greens first but fails the Theseus audit | Recorded as &quotrewrite won, in Swift" — Jonathan rules whether a Swift rewrite or the Python is the keeper; the race answered &quotrewrite beats salvage," not &quotSwift beats Python." |

| Neither greens by day 14 | Both halt. Evidence sets + ledgers to Jonathan. Nothing auto-fires, no auto-extension (PLAN-R2 §3 residual rule kept). |

| One lane halts at day 7 | Other lane runs to green or timebox; a walkover still requires the full heat + S23 — no green by forfeit. |

---

## C. The tool pile — one verdict each, with teeth

Every note below was read in full from ~/.notesq/vault/md/iCloud-Notes/ this round. Verdict ∈ USE now

/ TRY (bounded, with the proof-in condition) / NO (with the reason). Slot ∈ vessel · race-lane ·

product · GhOST-side. Cost is Jonathan-minutes (AI minutes are free by charter rule 5).

| Tool (note) | Verdict | Slot | J-min | The teeth |

|---|---|---|---|---|

| \*\*Herdr\*\* (Herdr-9128) | \*\*TRY — day-one vessel audition, pre-registered bars (A6)\*\* | vessel substrate → Lane P substrate if it passes | 15 (read the verdict table) | Proof-in: zero false idle/done over ~60 graded transitions, headless, kill-proof transcripts, no phone-home. Its detection is process-name + output heuristics — divination like ours; the audition asks only whether its divination beats our measured matrix. Fail → re-parked with the table as the reason. |

| \*\*Graphify\*\* (9018, 9118) | \*\*USE now\*\* | Lane S orientation (80k LOC to navigate for surgical deletion); never acceptance evidence | 0 | The 70x claim is about orientation cost, which is exactly Lane S's tax. Lane P gets little (fresh code has no archaeology). His own Tmux-alt-9017 shortlist names it — convergence, not novelty. Obsidian wrapper skipped (9118's own advice). |

| \*\*Zed\*\* (https-zed-dev-9091) | \*\*USE now\*\* (already the R2 install-now call; amendment-9 IDE answer) | Jonathan-side: reading lane diffs, spot-audits | 0 incremental | Package.swift LSP answers his stated SPM blocker; Sublime+LSP stays the familiar alternate; PyCharm last resort. The banned editor stays banned. |

| \*\*CodexBar\*\* (Peter-Steinberger-9114) | \*\*USE now\*\* | host telemetry: per-lane cap burn feeds the ledger + B4 cap rule | 5 (install) | Direct answer to vessel-leak #1 (shared caps are the one cross-lane channel the VM can't cut). 19.7k stars verified in the note via GitHub API, not search claims. |

| \*\*mcp-aggregator\*\* (Merge-MCP-9060) | \*\*USE, conditionally\*\* — baked into the golden only if an MCP cell (S27) survives the strike-pass | vessel plumbing | 0 (folded into auth hour) | One stable PID = one approval, baked at image time; kills per-clone popup friction. combine-mcp stays rejected (aggregator won the comparison in his own note). |

| \*\*Ponytail\*\* (Ponytail-9129) | \*\*TRY — in both lanes' authoring briefs, zero ceremony\*\* | race-lane bot discipline | 0 | The ladder is a paragraph in each lane's brief, not a dependency. Its note's own counterexample (6k tokens to conclude real code was needed) is respected: drop it from a lane's brief the first time it produces YAGNI-lawyering instead of smaller diffs. |

| \*\*Periphery\*\* (Dead-code-…-9113) | \*\*USE, Lane S only\*\* | post-deletion sweeps while Swift exists | 0 | Dead-code detection IS subtraction's instrument. Never a gate (the release gate stays dead). PMD/CPD skipped — 4 Swift rules, per the note. |

| \*\*Jean-Claude\*\* (9121) | \*\*TRY — steal the mechanism, skip the dependency\*\* | golden image, only if the vessel needs a second account profile | ≤10 (during auth hour) | The note's own conclusion: it is two `ln -s` calls (settings.json, hooks/). If the vessel runs one account set (recommended, A2 #1), even that is unneeded. |

| \*\*litellm\*\* (litellm-9008) | \*\*NO for the race; TRY later only on measured cap failure\*\* | product ops, post-race | 0 now | Named crux vs PLAN-R2 §8 (&quotfirst and only proxy ever trialed"): routing the CLIs through litellm swaps subscription OAuth for API-key billing — it changes the exact auth shape the golden image snapshots, and bills tokens at API rates his Max subscription already covers. The race must measure the product, not a re-plumbed billing path. If a real run hits caps twice (B4), litellm is the first and only proxy trialed — then, not before. |

| \*\*Maestri\*\* (9108) | \*\*NO as component; contact the author stands\*\* | — | 0 (10 if he writes Evert) | GUI canvas, no headless drive — nothing for a vessel to clone-cycle. The contact ruling (solo dev, same problem space, in Swift) survives on its own merits. |

| \*\*JetBrains Air\*\* (9110) | \*\*NO\*\* | — | 0 | It is the incumbent-adjacent competitor to the product itself; adopting mid-race dissolves the race. Reference ideas (worktree isolation, code-aware review) already absorbed into the study's language. |

| \*\*OpenHands\*\* (Openhands-agent-9076) | \*\*NO\*\* (R2 skim already banked) | — | 0 | A second orchestration platform inside the correction is scope creep — R2 ruling stands, nothing new in the note changes it. |

| \*\*acpx / ACP\*\* (ACP-9124, https-agentclientprotocol-9096) | \*\*NO for the race\*\* | possible far-future adapter seam | 0 | The note's own evidence kills it here: zed#52151 &quotACP agents frequently hang with no output" — importing a documented hang source into a race about reliability; and ACP standardizes the wire, not the nodes-stopping problem that created kicker. `--cwd` exists in acpx, but cwd-correctness is the product's hard part (THE-GOAL.md:108-110), not a flag. |

| \*\*A2A\*\* (9115) | \*\*NO\*\* | — | 0 | HTTP + OAuth + SSE between sibling processes on one Mac — the note's GhOST reply already said &quotwrong shape," and nothing in round 3 changes the shape of the machine. His fs-based-protocol instinct (&quotbees at the end") is the product's own channel design; the gap the note found (no fs+network JSONL protocol off the shelf) stays a someday-build, not a race item. |

| \*\*MemWal / Walrus\*\* (9148) | \*\*NO now — parked post-proof\*\* | product memory experiment, after S8/S18 answer package-native adequacy | 0 | Chain + relayer + network deps inside a hermetic vessel is anti-realism; worse, importing an external memory service CORRUPTS the warmth scenarios — S18 exists to prove the package alone carries identity. Revisit only if S8 fails and escalates the memory question (PLAN-R2 §9.7). |

| \*\*TencentDB Agent-Memory\*\* (9085) | \*\*NO now — parked, same gate as MemWal\*\* | product memory experiment | 0 | Team-governed memory bank competes with the one-truth collapse (§7 of PLAN-R2). It solves crew memory; the race must first prove the package's native memory (provider history + prompts) is or isn't enough. They queue behind S8's verdict, competing with each other, not with the plan. |

| \*\*memory-lancedb-pro\*\* (9088) | \*\*NO\*\* | reference design only | 0 | OpenClaw-specific plugin (before\_prompt\_build hooks); its note already concluded &quotreference, not install." |

| \*\*claude-mem\*\* (9106) | \*\*NO\*\* | — | 0 | AI-compressed opaque memory beside package + provider history + convoq = a fourth memory authority; the disease was parallel records. |

| \*\*Exo\*\* (9094) | \*\*NO for this study\*\* | inference fleet, off-plan | 0 | Inference clustering, not orchestration. The five-Mac fleet idea stays charming and stays parked. |

| \*\*CLIProxyAPI\*\* (Cli-proxy-9071) | \*\*NO\*\* | — | 0 | Rejected while litellm stands (R2 ruling) — and the litellm verdict above means no proxy at all until a measured cap failure. |

| \*\*Ds4\*\* (9120) | \*\*NO\*\* | hobby, off-plan | 0 | antirez's close-to-the-metal toy — &quotneat" (his word), zero orchestration relevance. |

| \*\*jCode / Pi / Cursor\*\* (9117) | \*\*NO / TRY-later / NO\*\* | Pi = 5th-brand candidate after the four pass | 0 | Pi's minimal-context thesis is real but a 5th brand mid-race is scope; jCode's RAM edge is irrelevant at crew scale; Cursor is an editor in the banned lineage, not a harness for tmux work. |

| \*\*Code-CLI-TUI-Hooks\*\* (9112) | \*\*NO as feature; evidence banked\*\* | — | 0 | The survey's finding (Codex PreToolUse fires only for Bash) is the receipt that a cross-brand hook abstraction doesn't exist — hooks stay absent in the golden image; every scenario passes with all hooks off. |

| \*\*Duck-code / Rubber Duck\*\* (9142) | \*\*Pattern USE, product NO\*\* | the pattern IS B2 #4 (out-of-family critics on every green) | 0 | GitHub's data validates cross-family checkpoint review; the race already runs it via GLM + DeepSeek. Copilot CLI itself adds nothing. |

| \*\*iMessage-with-robots\*\* (9116) | \*\*NO new adoption\*\* | GhOST-side already owns the slot | 0 | `imsg` is already brand-agnostic outbound (the note's own finding); race notifications ride the existing channel. Never liveness truth. |

| \*\*Marker\*\* (9119) | \*\*NO for kicker\*\* | GhOST/legal-side | 0 | PDF conversion; wrong universe. Its shared-wrapper shape advice is good and already GhOST's pattern. |

| \*\*Obsidian\*\* (9111) | \*\*NO for kicker\*\* | GhOST-side vault, already served | 0 | Dataview/Git plugins are @astra-pipeline business, not race business. |

| \*\*Kimi K3\*\* (9125) | \*\*NO now\*\* | later, OpenRouter-ZDR only | 0 | Privacy line honored (no train-on-use); no seat in a claude/codex/qwen(/agy) heat. |

| \*\*Peekaboo / mcporter / gogcli / agent-scripts / summarize\*\* (9114) | \*\*NO / later layers\*\* | — | 0 | Unchanged from R2: developer-side conveniences, none touch the race graph. |

| \*\*Piebald\*\* (Piebald-9123) | \*\*Out of scope — no researched reply exists\*\* | — | 0 | The note is a bare question with no GhOST reply; inventing a verdict would be exactly the unconsidered-pile failure this workstream corrects. Flagged for a research pass if he still cares. |

| \*\*Tart\*\* (amendment 1; Exo-9094's &quottart.run" aside) | \*\*USE — it is Workstream A\*\* | the vessel | 45-60 (auth hour) + ≤15/month | The whole of section A. Not installed yet on the M4 Pro (verified); commissioning is the first vessel act. |

| \*\*tmux notes\*\* (Tmux-9109, -9066, Tmux-alt-9017) | \*\*USE as reference\*\* | Lane P glue (display-message inventory), harness adapter | 0 | 9109 is a ready-made cheat sheet for the harness's tmux backend. Tmux-alt-9017 is his own three-line shortlist — Herdr, Graphify, Ponytail — and this round's verdicts land TRY/USE/TRY on exactly those three: the pile was less unconsidered than it felt; it was unANSWERED. |

| \*\*9137 / 9138-9140\*\* (first-plausible-answer; harness settings) | already encoded | method, not tools | 0 | Counterexamples-first is the study's standing rule; guardrail/stop-hook notes stay wired to exactly one real scenario, never back to green tests. |

Cruxes worth naming for the adjudicator (where a counterpart node could reasonably split): litellm

(race-time NO here vs R2's trial-when-needed — the auth-shape argument is the crux); Herdr (my

audition bars are strict enough that I expect it to FAIL them — a node that expects it to pass should

say which bar it relaxes); Lane-P-may-read-Swift (I allow it; a stricter node would firewall it — my

ground: amendment 5 says knowledge transfers, and the Swift can't leak passing behavior it never had).

---

## D. PREDICTION BLOCK — stakes in the ground

\*\*Winner, flat: Lane P (Python) — by Jonathan-attention-minutes, the primary clock.\*\*

\*\*Confidence: 65%.\*\*

\*\*Margin:\*\* P greens the heat at ≈100-150 J-minutes; S at ≈220-320. Expected margin \*\*≈120-170

J-minutes\*\*. Wall-clock: P green at day 7-10, S at day 10-14 with ≈35% timebox-miss risk — \*\*P by 2-4

wall-days\*\*. Why the asymmetry: the clock counts HIS minutes, and Lane S's failure modes are

archaeology — which of four systems of record lied, which half of the half-migration bit — the exact

failure shape that historically escalates to Jonathan for rulings; Lane P's failure modes are

young-code bugs in ~5-8k fresh lines that bots fix without him. Secondary drag on S: 80k-LOC Swift

rebuild cycles inside a scenario-fix loop vs Python's instant loop. Both lanes have a working binary

on day one (S's is built — .build/debug/kicker, Aug 5; P's is convoq-adjacent scaffolding), so neither

starts from zero; the loop-speed and failure-shape gaps are the whole bet.

\*\*Single fastest falsifier of my call:\*\* Lane S turning S5 green (kickerd killed mid-run, crew

messaging continues — or the daemon excised outright) \*\*within the first 48 hours\*\*. That would prove

Keel's excision map (BusDelivery.swift / ConductorNodeSupervision.swift:50 /

BusDeliverySupport.swift:97 / WatchdogPass.swift:27) is surgical rather than archaeological, and the

rest of Lane S's heat is mostly behavior the system already exhibited under kickerd for weeks — my

J-minute asymmetry collapses and S likely takes both clocks. The mirror falsifier against P: failing

any of the four substrate-subprocess proofs (stale capture, option race, non-atomic paste+submit,

socket bind) repeatedly in week one — if Python can't own the pane, the matrix can't save it.

\*\*Secondary stakes:\*\*

- \*\*Herdr does NOT take the substrate seat — 60%.\*\* Predicted failure: one false idle/done during a

claude long tool-use turn or a permission-prompt &quotblocked" misread, against pre-registered bar #1

(zero false dones). It survives as console/observer candidate; the measured table re-parks it. (If

it passes, I am wrong in the good direction: an entire glue category exits Lane P's scope.)

- \*\*The Tart bed survives contact — 75%.\*\* First breakage, named: headless auth — Claude Code's

keychain-backed credentials failing under SSH in the first clone-cycling day, costing ~half a day of

vessel plumbing and fixed by the setup-token env path already staged in A2. Second breakage

candidate: RAM sizing on the S23 cell (48GB host, 15+ provider processes in one guest → the cell

moves to the M5 Max).

- \*\*Tool that ends up mattering most: Graphify\*\* — Lane S's subtraction navigation is the

highest-leverage grunt work in the race, and it is also the tool that keeps mattering after the race

regardless of winner. Conditional override: if Herdr passes its audition, Herdr matters most (it

deletes a whole category of Lane P glue AND replaces the matrix's most fragile knowledge with an

API), but I have already staked 60% that it does not.

- \*\*Bonus stake, because the book should grade it:\*\* the strike-pass removes at least S3's per-brand

cells and one of S9/S10/S22 entirely (the catalog's own VETO CANDIDATE flags are well-aimed), and

no scenario I listed in the heat at B1 gets struck outright. If he strikes a heat scenario, my heat

design misread his words, and that itself is graded against reality.

\*— Fable node, R1 of round 3. Written for the book: every number above is checkable, and several are

designed to be wrong quickly rather than vague forever.\*