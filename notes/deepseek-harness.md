**Deepseek harness**

@ghost

Interesting new LLM harness. In preview now.

Everything is a plugin. Everything is traceable.

**GhOST research (2026-08-14):**

Real. DeepSeek Harness (dsh), a developer preview open-sourced within the last day, MIT license, source at github.com/deepseek-ai/deepseek-harness.

**Architecture:** built on their own “Cordis” plugin kernel. Every capability — models, tools, skills, sessions, sandboxes, storage, loops, scheduling, even the UI — is a swappable plugin, composed via config with no source changes needed. Their own framing: “the model is the soul of an agent, the harness is what keeps it working in real-world environments.”

**Traceability:** every run writes an append-only session log — system prompts, reasoning, tool calls/results, subagent scheduling, every context injection. A “Trajectory view” inspects it by source; resume/fork/search/replay all operate on that same event stream.

**Four runtime modes:** Standard (full coding agent — file editing, shell, search, skills, planning, goals, subagents, workflows), Code mode (tools exposed via a Code Mode SDK so the model writes one TypeScript program to orchestrate multi-step tool calls instead of separate calls), Minimal (just a shell + file editor, for benchmarking a model in a bare environment), Creator mode (inspect the live runtime, test Cordis plugins in memory, author new presets).

**Try it:** npx @deepseek-ai/dsh web (needs Node.js) or clone the repo directly.

*One dev outlet (developersdigest.tech) reported reading the actual source: ~453K lines, built on a vendored fork of the Cordis meta-framework.*

* Everything is a plugin. Everything is traceable.

@ghost. Put this pretty high on the tech to try list

**GhOST reply, 2026-08-19:**

Done — placed at the top of section A, the orchestration substrate list, in the canonical tech-to-try in @astra (commit 25448f8).

Kept the traceability detail prominent in the entry, because that is the part that bears on kicker rather than on general interest: an append-only event log per run covering system prompts, reasoning, tool calls and results, subagent scheduling and every context injection — with resume, fork, search and replay all operating on that one stream. Kicker has been hand-rolling pieces of exactly that.