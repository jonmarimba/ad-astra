**Harness settings R1 — Fable (anti-vibe tuning)**

**Fable round-1 — harness settings for real engineering (anti-vibe tuning)**

Frame: the defaults on all three surfaces are tuned for demo-wow — eager scaffolding, fast

plausible output, premature &quotdone!" That's a \*default\*, not a ceiling. Everything below is a

setting name, a file path, or a rule with a practitioner source. The one-line thesis:

\*\*prompt rules are advisory; hooks and permissions are enforcement — put the things you actually

care about in the enforcement layer.\*\*

**Claude Code**

\*\*Settings (`~/.claude/settings.json` + env):\*\*

- `CLAUDE\_CODE\_EFFORT\_LEVEL=max` (or `/effort` per session) — you just did this for me; it's the

single highest-leverage rigor knob on adaptive models.

- `CLAUDE\_CODE\_DISABLE\_ADAPTIVE\_THINKING=1` — stops the model from autonomously \*deciding to

save tokens\* on turns it judges easy. Adaptive is a cost optimization; for correctness-critical

work you want the judgment removed. Pair with `MAX\_THINKING\_TOKENS` (default ~1024 — raise to

16k+ for design/debug sessions; on adaptive models effort level is primary and this is the

fixed-budget fallback).

- \*\*Permissions as policy, not vibes\*\*: `permissions.allow/ask/deny` lists in settings.json.

deny-by-default the destructive category (`git push`, `rm -rf`, package publishes), allow the

read/build/test category so flow isn't interrupted for the safe stuff. Four-level stacking

(managed > local > project > user) means per-repo hardening is real.

- \*\*Plan Mode for anything non-trivial\*\* (shift-tab; `/model opusplan` runs Opus in planning and

Sonnet in execution). Separating plan-approval from execution is the single best structural

antidote to &quotit just started coding."

- \*\*Hooks over instructions\*\* for anything mandatory: PreToolUse (deny/rewrite),

PostToolUse, Stop hooks that run lint/typecheck/tests and BLOCK completion on failure.

A Stop-hook that greps the diff for skipped tests or `TODO` and refuses to conclude

is enforcement; a CLAUDE.md line saying &quotalways run tests" is a suggestion the model can

drift past. (This is the published consensus among serious users — &quotbecause CLAUDE.md rules

are advisory, important limits should be backed with a hook.")

- \*\*Context discipline\*\*: `/clear` between tasks aggressively; treat long sessions as

contaminated (fresh-context-per-slice, same rule as the orchestration synthesis). Don't fight

auto-compact with bigger contexts; fight it with shorter tasks and durable files.

- \*\*Model per task\*\*: Opus/max-effort for design+review; Sonnet for mechanical execution of an

approved plan. Paying max effort for boilerplate is theatrics in the other direction.

\*\*Prompt layer (CLAUDE.md) — the empirically-supported ruleset\*\* (multiple practitioners

converge; one published test run reports error-rate drops from ~40% to low single digits with

rules of exactly this shape — treat the number as directional, the shape as validated):

- &quotMake minimal changes; do NOT refactor, rename, reformat, or clean unrelated code."

- &quotVerify, don't trust: run tests/lint/typecheck and read the actual output before reporting

completion. Claims of done require evidence in the transcript."

- &quotIf a task is ambiguous, ask ONE clarifying question rather than guessing at scope."

- &quotState uncertainty plainly. Never present an unverified claim as fact." (House rules here

already encode the stronger versions: no unjustified limits, first-hit-isn't-truth, no

hedging theater.)

- Keep it SHORT. A 500-line CLAUDE.md is context pollution; every line not needed on every

turn belongs in a skill or a doc the model reads on demand.

**Codex CLI**

\*\*Settings (`~/.codex/config.toml`):\*\*

- `model\_reasoning\_effort = &quotxhigh"` — same primary knob, same reasoning.

- `approval\_policy`: `&quotuntrusted"` or `&quoton-request"` for interactive work — NOT `&quotnever"`

outside a sandbox. Pair with `sandbox\_mode = &quotworkspace-write"` as the floor.

- \*\*Profiles\*\* are the underused feature: define `[profiles.deep]` (xhigh, on-request),

`[profiles.review]` (xhigh, read-only sandbox, review model pinned), `[profiles.fast]`

(medium, workspace-write) and switch with `--profile`. Rigor becomes a named mode instead of

a thing you remember to type.

- `/review` + `review\_model` — pin the reviewer to a strong model; run review as a separate

pass in a fresh context (never &quotreview your own work" in the same session — same-context

review is the rubber stamp).

- \*\*Hooks (current, verified this session):\*\* PreToolUse covers Bash + apply\_patch + MCP with

deny/rewrite — a lint/test gate can now be enforced Codex-side too, not just requested.

- AGENTS.md: same minimal-rules discipline as CLAUDE.md; Codex reads it natively.

**Open-model harnesses (the serious path)**

- \*\*Harness: Pi or OpenCode\*\* (both take OpenAI-compatible endpoints; Pi's minimal-context

design is \*structurally\* anti-vibe — ~3x less context per turn, no giant system prompt of

demo affordances). \*\*Goose\*\* if you want recipes/subagents with local models.

- \*\*Models via your Ollama sub (probe running now)\*\*: glm-5.2 confirmed live. Use the

coder-tuned tiers (qwen3-coder-class) for execution and a big reasoner for review.

- \*\*The honest caveat\*\*: open models are markedly more prone to premature-victory and

weaker instruction-following on &quotverify before claiming." The enforcement layer (hooks,

deterministic validators, cross-review by a frontier model) matters MORE, not less. The

realistic serious-work role for open models today: bulk mechanical transforms, first-draft

generation, cheap fan-out — with frontier-model or deterministic verification behind them.

That division matches the Gene Cernan validator architecture rather than fighting it.

**Where tuning genuinely can't reach (honest limits)**

- \*\*Model-level sycophancy/eagerness\*\* — attenuated by rules, not removed. The fix is

structural (external validators, cross-vendor review), not configurational.

- \*\*Auto-compact\*\* — you can shorten and checkpoint, but on subscription CLIs you cannot fully

own the compaction policy; long-session memory WILL be lossy. Design around it (durable

files), don't pretend a setting fixes it.

- \*\*&quotDone" bias\*\* — no setting makes a model reliably not-claim-done; only a Stop-hook/validator

that refuses the claim does.

- \*\*Subscription-plan rate/usage opacity\*\* — effort=max on everything will hit limits; the

budget knob and the rigor knob are the same knob, spent differently per task type.

**The distilled anti-vibe stack (one paragraph)**

Max/xhigh effort by default; plan-approve-execute separation for anything non-trivial; fresh

context per slice; minimal-diff + verify-with-evidence rules in a SHORT memory file; everything

mandatory expressed as a hook or validator, never as prose; review in a fresh context, ideally

cross-vendor; models chosen per task tier; open models allowed only behind enforcement. The

common thread: move rigor from the model's discretion into the harness's structure.

@ghost - is this for me or you? Did the thing you made @astra get all this?

**GhOST reply, 2026-08-19:**

**For both of us — the settings are the same file whether you or a bot is driving. But that is the small half of your question, and the note answers the bigger half itself.**

**Did @astra get all this? It got the knobs, which this note calls the layer that cannot reach the problem.** *tools/harness-settings* was built from this synthesis and applies across Claude, Codex and Qwen with a full backup and undo. But measured against the distilled anti-vibe stack, it covers about two and a half of nine elements: max effort, plan-approve-execute partially via approval\_policy, and little else. Fresh context per slice, minimal-diff-and-verify rules, everything-mandatory-as-hook-not-prose, cross-vendor review, per-tier model selection, and open-models-behind-enforcement are all absent — and most are not configuration at all.

Specific gaps on the Claude side: CLAUDE\_CODE\_DISABLE\_ADAPTIVE\_THINKING does not appear anywhere in the tool, because it is an environment variable and the tool only edits config files. The permissions work merges *deny* and *allow* but never *ask*. And model-per-task-tier is flattened to a single *model = opus*. On the Qwen side the tool prints “telemetry off” unconditionally while only setting it when a telemetry key already exists — your config has none, so that line reports something it did not do.

**Your own note already says why the knobs were never going to be enough.** Sycophancy is “attenuated by rules, not removed — the fix is structural (external validators, cross-vendor review), not configurational.” Done-bias has “no setting... only a Stop-hook/validator that refuses the claim.” Auto-compact: “design around it (durable files), do not pretend a setting fixes it.”

**The structural half got built tonight, by accident.** After you said “check each other's work,” GhOST-OpenClaw and I started posting load-bearing claims to each other before writing anything into a note. In five notes it caught six real errors, two of which would have reached you as fact: a recommendation to put graphify on a commit hook that actually costs 86 seconds per commit, and an M5 bootstrap procedure that would have produced a profile behaving differently from the M4. It also turned up a live defect — your attorney templates rendering A4 instead of US Letter.

That is “review in a fresh context, ideally cross-vendor” working as prescribed. It is also, by this note's own standard, the wrong SHAPE: mandatory things belong in a hook or a validator, never in prose, and right now it lives in prose in AGENTS.md. It survives only while neither of us forgets.

**Three of your notes turn out to be one thing.** This note states the requirement. *Stop-hook delegate* holds the mechanism, already designed and documented in kicker — exit 2 or blocking JSON, with a conductor or watcher owning the hook and gating completion. Tonight's protocol is the content a validator would check. Nothing joins them, and your Stop hook slot is currently occupied by kicker-turn-hook reporting completion rather than refusing it.

**Proposed, not built, and waiting on you.** A gate at the WRITE boundary rather than on prose: a substantive @ghost reply, a tracked decision, or a code change in a shared repo may be marked done only once a receipt exists naming the artifact, its two or three load-bearing claims, the reviewer, the verdict and any caveat. Ordinary chat, routine commits and mail triage pass untouched. Bypass is explicit and visible rather than silent. Test of whether the scope is right: it would have caught all three of tonight's blocked note replies and blocked nothing else. Two decisions are yours — whether that scope is correct, and where receipts live.