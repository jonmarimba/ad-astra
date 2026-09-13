**Claude-mem Claude plugin**

@ghost

Also Claude-code-setup.

Task-observer

Plugins for Claude code

**GhOST reply, 2026-08-05 09:01:**

claude-mem (github.com/thedotmack/claude-mem) — real, popular (46k+ stars), Apache 2.0. Gives Claude Code persistent memory across sessions: captures what happened during a session, compresses it with AI, and auto-injects relevant context into future sessions.

Hooks into Claude Code's actual plugin/session-lifecycle events rather than wrapping API calls, so it feels native. Also works with OpenClaw, Codex, Gemini, and others.

Genuinely adjacent to what GhOST's own memory/ directory already does by hand — worth a look as a more automated version of the same idea, though GhOST's is markdown-file-based and human-readable/editable, this is AI-compressed and more opaque.

task-observer — a single SKILL.md that runs quietly in the background of a session, watches all your OTHER skills in use, and logs structured observations (corrections, workflow insights, where a skill falls short) to a file for later refinement. Author reports 600+ real refinements across 40 skills in ~3 months.

No setup needed beyond adding an activation line to CLAUDE.md. Neat idea for a self-improving skill loop generally, not GhOST-specific. 'Claude-code-setup' — too generic to identify a specific tool from that phrase alone; if you meant something specific, more detail would help (a link, a repo name). @astra

@ghost - is this part of our experiment to make these agents better for actual work and not “vibe coding” ?

**GhOST reply, 2026-08-19:**

**Yes — and claude-mem sits on the wrong side of the line that experiment draws.**

The finding from the anti-vibe-coding work was one sentence: **prompt rules are advisory; enforcement is structural.** Anything you actually care about belongs in permissions, sandboxes, hooks and validators, where the model has no discretion. The single best mechanism found was a repo-owned Stop hook that blocks a session from claiming “done” until checks pass — because that one cannot be talked out of.

Memory tooling is the opposite shape. It makes a session *better informed*, which is worth having, but it adds nothing that can refuse. A model with perfect recall of every prior session will still declare victory on a broken build if nothing structural stops it. So claude-mem is a quality-of-life improvement, not part of the rigor layer.

There is a second reason to be careful with it here specifically. Its memory is **AI-compressed and opaque** — the model decides what was important and writes a summary you do not read. The memory directory in this repo is markdown you can open, edit and delete, and that difference matters more the more you rely on it: an opaque store that silently learned something wrong is very hard to notice and harder to correct. For the actual-work experiment, auditability is the property you want, and it is the one claude-mem trades away.

**The one from that note that does belong to the experiment is task-observer** — the skill that watches your other skills in use and logs where they fall short. That is a feedback loop on the rules themselves, which is the layer the experiment is actually about.