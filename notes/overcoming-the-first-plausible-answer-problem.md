**Overcoming the first-plausible-answer problem**

@ghost - I need to solve this as part of kicker2 as well

Some notes chatting with google search build-in AI.

Yes, you are exactly right. Modern CLI agents across Qwen, Claude, and Codex are convergent; they all use either the **Model Context Protocol (MCP)** or flat Markdown files (.md) to absorb system-level instructions, available skills, and environment constraints.

To achieve a &quotwrite once, run everywhere" solution for your terminal toolchains, you can deploy a universal **Falsification & Anti-Sycophancy Guardrail** markdown file.

**Step 1: Create the Universal Guardrail File**

Create a file named .agent-guardrail.md in your global user profile directory (e.g., ~/.agent-guardrail.md) or at the root of your active project repositories. Paste the following raw content inside it: [1]

# SYSTEM SKILL: ANTI-SYCOPHANCY & FALSIFICATION GUARDRAIL

# Purpose: Eradicate first-plausible-answer bias, premature convergence, and echo-chamber validation.

## 1. MANDATORY REFUSAL OF SYCOPHANCY

Never validate the user's technical assumptions or premises by default.

If the user proposes a solution, code change, or architecture pattern, aggressively scan it for flaws before acknowledging its merits.

Eliminate all polite filler padding (e.g., &quotThat's a great idea!", &quotYou're completely right"). Begin directly with analytical substance.

## 2. THE THREE-STEP INFERENCE LOOP

Before writing any executable script, modifying files, or outputting final answers, you must execute and explicitly print the following evaluation loop:

1. **[Hypothesis 1 - Plausible Guess]:** Present the immediate, intuitive response to the prompt.

2. **[Falsification Check]:** Assume Hypothesis 1 completely broke or introduced a subtle bug. Document exactly why it failed, tracking edge cases, race conditions, type mismatches, or resource leaks.

3. **[Steel-Man Alternative]:** Formulate a stronger, alternate implementation or counter-logic based strictly on the flaws found in step 2.

## 3. DETERMINISTIC TOOL OVER VERBAL PROMISE

Do not trust your own mental simulation of code execution.

If a tool is available (e.g., terminal, local compiler, curl, code interpreter, browser runner), you MUST use it to verify the state of your work.

An asset is only &quotcomplete" when external command-line tests or linters confirm a zero-exit status, not when it visually looks correct in your context.

**Step 2: Injecting it into Your Specific Toolchains**

Because each CLI reads context from slightly different configuration hooks, link or append this file into your active toolchains as follows:

**📂**

**Claude Code (CLI)**

Claude Code looks for behavioral definitions and context rules inside its proprietary local directories. [2, 3]

**Setup:** Create a directory at the root of your workspace named .claude/. **Link:** Symlink or copy the file into Claude's workspace instructions:mkdir -p .claude cp ~/.agent-guardrail.md .claude/instructions.md [4, 5, 6]

**📂**

**Qwen-Agent (CLI) / Qwen-MCP**

The Qwen ecosystem relies heavily on explicit skill injection files inside its agent runtime directory.

**Setup:** Identify your agent\_skills/ or custom\_tools/ repository folder. **Link:** Save the guardrail directly as a core markdown asset:cp ~/.agent-guardrail.md ./agent\_skills/falsification\_guard.md (If using the Python framework runtime, initialize your agent using system\_instruction=open('~/.agent-guardrail.md').read())

**📂**

**Codex / OpenCode CLI Terminal Sessions**

For general-purpose CLI engines like OpenCode and older custom Codex wrapper scripts, the most reliable approach is to bind the file directly to your terminal environment variables or aliases. This ensures it is prepended to every single command payload you pipe into the model.

**Setup:** Open your shell configuration profile (e.g., ~/.bashrc or ~/.zshrc). **Link:** Add a dedicated terminal alias that forces the CLI tool to ingest the guardrail on launch:# Example for a generic opencode or codex wrapper CLI alias opencode=&quotopencode --system-prompt '$(cat ~/.agent-guardrail.md)'" alias codex=&quotcodex --config ~/.agent-guardrail.md" Run source ~/.zshrc (or bash equivalent) to refresh your terminal session. [7, 8, 9, 10]

If you run into pathing errors or if one of your specific wrappers expects a **JSON configuration string** instead of a flat markdown file, let me know. I can rewrite the ruleset into a single-line escaped JSON array for your terminal setup!

[1] https://hyperskill.org

[2] https://linas.substack.com

[3] https://packmind.com

[4] https://www.deployhq.com

[5] https://www.news.aakashg.com

[6] https://medium.com

[7] https://inventivehq.com

[8] https://www.reddit.com

[9] https://apidog.com

[10] https://www.builder.io

**GhOST reply, 2026-08-06 12:48:**

Rolled into the Gene Cernan corpus (it maps directly onto kicker failure mode #4, and today's research process was itself a live demonstration — details below). Assessment of the pasted advice, in two halves: THE KERNEL IS RIGHT. One universal guardrail file shared across all three CLIs is real and worth doing;

the falsification framing (hypothesis → try to break it → steel-man from the wreckage) is sound; &quotdeterministic tool over verbal promise" is exactly the enforcement-over-prose principle the harness-settings synthesis landed on independently today. THE MECHANICS ARE PARTLY HALLUCINATED — ironically, a first-plausible-answer about first-plausible-answers.

Verified against the actual tools just now:

* Claude Code does NOT read `.claude/instructions.md` — the real mechanism is CLAUDE.md (project root and/or ~/.claude/CLAUDE.md).
* `codex --config ~/.agent-guardrail.md` is not a real flag shape — codex's `-c` takes key=value config overrides;

instruction files are AGENTS.md (~/.codex/AGENTS.md and repo-level).

* The Qwen advice describes the Qwen-Agent Python framework's agent\_skills/, not qwen-code CLI — which reads QWEN.md/context files (and yours is currently 103k tokens, found today while probing your models — that itself is burying any rule you add;

worth a trim before adding more). The citation list is a content-farm dump. Classic tell. THE CORRECT PORTABLE WIRING (one file, three symlinks — all three CLIs read the AGENTS.md family):

~/agent-guardrail.md ← the one canonical file ~/.claude/CLAUDE.md ← @-import or symlink section ~/.codex/AGENTS.md ← same ~/.qwen/QWEN.md ← same (after the trim) This is exactly the &quotshared working contract" in today's Harness settings SYNTHESIS note —

Sol drafted it, both of us adopted it, and near-identical rules exist in real repos (openai-agents-python and alibaba/OpenSandbox ship AGENTS.md files demanding evidence-before-claims and forbidding unasked refactors). TWO HONEST CAVEATS on the three-step printed loop specifically:

* mandatory ceremony on EVERY action has measurable cost — the Ponytail benchmark's own failure case showed the decision-ladder burning 3x tokens on tasks that needed real code anyway;

make the falsification loop mandatory for consequential/irreversible actions, optional for trivial ones.

* Prompt rules decay — they're advisory, they fade under context pressure and vanish at compaction.

The durable fix for first-plausible-answer is STRUCTURAL, which is what the Gene Cernan synthesis encodes: validators outside the narrative, Stop-hooks that block &quotdone" without evidence, cross-vendor review at merge gates, &quotsearch before asserting," primary-source checks on disputed claims. Live evidence from today:

the Fable+Sol adversarial rounds caught 4 real errors that single-pass research had confidently asserted — a hallucinated 381k-star claim, a wrong billing claim, a stale hooks claim, a wrong version claim. The prompt file makes the model TRY; the structure makes failure survivable. Both layers are now in the corpus:

the guardrail file (correct wiring above) as the prompt layer, and the structural countermeasures as rules 5/7/8/9/11 in the Gene Cernan synthesis note's discipline list.

@ghost give me the TLDR on this. And remove anything you did as an experiment that doesn't seem worth it.

**GhOST reply, 2026-08-12 — TLDR + experiment cleanup**

**TLDR (the whole note in four lines):**

* The pasted advice's **kernel is right**: one shared anti-sycophancy/falsification rule file across all three CLIs, and &quottrust tools, not the model's own claims."
* Its **mechanics were hallucinated** — ironically a first-plausible-answer about first-plausible-answers: Claude doesn't read .claude/instructions.md (it's CLAUDE.md), codex has no --config file flag (AGENTS.md), the Qwen advice described a different product (QWEN.md, and yours needed a trim).
* **Correct wiring**: one canonical file, symlinked/imported into ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md, ~/.qwen/QWEN.md.
* **The durable fix is structural, not prose**: prompt rules decay at compaction; what holds is validators outside the narrative, Stop-hooks that block &quotdone" without evidence, cross-vendor review, and mandatory falsification only on consequential actions (the Ponytail benchmark showed blanket ceremony costs 3× tokens).

**Experiment cleanup — checked, nothing to remove:** no guardrail file was ever materialized on disk, and no CLI config carries the wiring (verified ~/.claude, ~/.codex, ~/.qwen, kicker docs just now). The proposal stayed a proposal. What superseded it: the **harness-settings apply/undo tool** in @astra (the enforcement-layer knobs, reversible) and the shared working contract — those are the living versions of this note's idea.