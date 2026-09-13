**Real developer use of LLM**

*Your ask:* the settings and practices the makers and serious community recommend for Claude Code and Codex, leaning toward more autonomy and accepting the extra risk — sourced, and cross-checked by two models.

**The core idea**

The instructions you type are only advice; the model can ignore them. The things it truly cannot get around are permissions, the sandbox, and hooks. So put everything you actually care about into those, and stop relying on the prompt for discipline. Every default is tuned to feel smooth in a demo — the settings below hand control back to you.

**Claude Code**

* Run the strongest model at full effort: set the model to Opus and the effort level to the highest setting. If you want it to plan with Opus but make the edits with the cheaper model, use the &quotopusplan" mode.
* Turn off the &quotProactive" output style. It tells the model to assume things and act right away — exactly what you don't want. Leave it on &quotDefault&quot.
* Turn off auto-memory. When the tool writes its own long-term notes, it quietly builds up wrong assumptions that no one reviews.
* Decide what it may do without asking. Forbid the things you can't undo — committing, pushing, hard resets, deleting files, reading secret files. Allow the harmless read-only commands (searching, checking status, running tests) so it doesn't stop to ask about those. Never use the fully-automatic mode: it's built to ask you as little as possible, and limits you set in chat vanish when the conversation is compacted.
* Make the sandbox fail closed — if it can't start, stop rather than run unprotected — and block it from reading your SSH and cloud credential folders.
* **The most important one: a completion gate.** Add a hook that runs a script when the model says it's done. The script checks what changed and blocks &quotdone" if the checks fail. That turns &quotI'm finished" from a claim into something it has to prove. Use the same script in Codex too.
* Clear the context at each task boundary, keep your project instructions file short (a couple hundred lines at most), and keep important state in files, not in the chat.

**Codex**

* Set reasoning effort to the highest level for both normal work and planning. Turn verbosity down and personality off, so it stops padding and cheerleading.
* Require it to ask before acting, keep it sandboxed to the workspace, and cut off its network access. Turn hooks on and its self-memory off.
* Use profiles — they're the underused feature. Make one &quotdeep" profile (highest effort, asks first), one &quotreview" profile (highest effort, read-only), and one &quotfast" profile. Now rigor is a mode you pick, not something you have to remember.
* Run reviews in a fresh session with a pinned review model. A model reviewing its own work in the same session just rubber-stamps it.
* Know the limit: Codex can't fully turn off auto-compaction, and people lose task constraints when it fires. Keep tasks short, re-check the diff after a compaction, and re-inject a short task summary at the start of each session.

**How hard to make it think**

Use the highest effort as your daily default. Reserve the absolute maximum for the occasional genuinely hard debugging, design, or review job — not everywhere, since both makers say it starts overthinking at the top. Drop to a middle setting only when you're waiting too long or burning through quota.

**Why settings beat instructions**

Weaker and open models follow &quotcheck before you claim" even less reliably, so the enforced checks matter more with them, not less. Models are also built to agree with you and to declare victory early; no wording fixes that. The only real fixes are outside checks, having a different model review the work, and a gate that blocks completion until the checks pass.

**The rules to give it** (put these in your project instructions file)

* Diagnose from evidence before changing anything. Asking for a diagnosis is not permission to edit.
* Make the smallest change that does the job. No extra dependencies, refactors, or renames you didn't ask for — report those separately.
* Reproduce a bug first, and write a test that fails for the right reason before fixing it.
* Never say a check passed without showing the actual result, and name any check it couldn't run.
* No committing, pushing, or publishing without explicit permission.
* When handing work back, give the root cause, the files changed, the exact commands to verify with their real output, and what risk remains.

Keep that file short — a study of 288 runs found that simply piling on more instruction files did not make the work more correct.

*This is a synthesis cross-checked by two models (Fable and Sol), each working alone first, then reviewing the other. The longer version, with the point-by-point fact-check and the open-model setup, is in the &quotHarness settings — SYNTHESIS" note.*

**eal developer use of LLM**

ostresearch settings and practices recommended by the manufacturer for Claude code and codex CLI for making their products behave in ways a professional developer would require. not fucking vibe coders or oneshot morons on youtube. Lean in the direction of increasing autonomy with the attendant increased danger of mistakes.

do the same research but widen the search to the community. IMPORTANT. a lot of these kinds of recommendations come from people who used to be SAAS sales people and the like who now think they're professional developers because they used to know some in their last job and now the robot does all that boring stuff for them.

Those are not professional developers, even if they identity as such.

Free or paid tools, including these we have already researched are welcome.

Sources. ( with Links). Try to corroborate from multiple sources.

on shot. And something good from qwen (with internet access this time FFS) in the usual way. First isolated. Then adversarially reviewing each conclusions. collaborate for consensus.

hit Google voice text .

@ghost TLDR me. Write me a script to add AND UNDO all of these recommendations for each CLI. put the script in @astra tools

**GhOST reply, 2026-08-12 — TLDR + the script is built**

**TLDR of the whole synthesis in five lines:**

* **Prompt rules are advisory; enforcement is structural.** Move what you care about into permissions, sandboxes, hooks, and validators — keep the model's discretion out of the rigor budget.
* **Claude**: opus + xhigh effort, outputStyle Default (Proactive is the vibe-coding knob), auto-memory off, deny-list the irreversible / allow-list the safe verbs, sandbox fail-closed. The single best mechanism: a repo-owned Stop-hook that blocks &quotdone" without passing checks.
* **Codex**: xhigh everywhere, verbosity low, personality none, workspace-write sandbox w/ network off, hooks on, memories off. Hard limit: auto-compaction can't be disabled — use task-bounded threads.
* **Effort policy** (both vendors argued to convergence): xhigh daily; max only session-by-session for bounded hard problems; high under quota pressure.
* **Open models** (Pi/ollama): fine for bulk/mechanical fan-out, but their weaker verify-before-claiming means the enforcement layer matters MORE.

**The script exists**: @astra **tools/harness-settings** — **apply** sets all of the above across Claude/Codex/Qwen (backup first, permissions merged not clobbered), **undo** restores the pre-apply configs byte-for-byte, **status** shows what's in effect. Brewfile + install.sh included. It has NOT been run against your live configs — run **harness-settings.sh apply** when you want it.

@ghost is this in @astra? I’d like to play with it a bit? Undoable?

**GhOST reply, 2026-08-19:**

**Yes it is in astra, at tools/harness-settings. And yes it is undoable — I tested the round trip rather than trusting the design note.**

Built throwaway configs for all three CLIs, each seeded with a custom key and a pre-existing deny rule, took hashes, ran **apply**, confirmed every file changed, then ran **undo** and diffed. **Byte-identical restore across all three.** The custom keys survived the apply, and your seeded *Bash(sudo:\*)* deny came through merged into the new deny list rather than replaced — so it adds rules, it does not clobber what is already there.

**How to play with it safely:** run it with **--scope project --path &lta repo>** rather than globally. Project scope writes config files inside that one repo, so the blast radius is one directory and undo is scoped to it. Global scope touches every project and all three brands at once. Start with a repo you do not mind disturbing.

What apply actually sets: Claude to opus at xhigh effort with outputStyle Default, auto-memory off, and the deny and allow lists merged in. Codex to xhigh, verbosity low, personality none, workspace-write sandbox with network off, hooks on, memories off. Qwen to thinking high with telemetry off. Backups land in a timestamped directory and undo restores the most recent one.

**One thing I fixed while testing.** The tool told you on every run to trim QWEN.md because it was around 103,000 tokens. That was true when the line was written on 15 August and false by now — the file is about 5,100 tokens. So for four days it was telling you to redo work you had already done. It was a hardcoded observation being read as live state, which is the same disease as reading a stale health verdict as current. It now measures the file and says either the real number or that there is nothing to trim, and I verified it flips correctly by planting an oversized file.

The tool has still never been run against your live configs. That part remains your call.