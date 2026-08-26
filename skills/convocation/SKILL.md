---
name: convocation
description: Run N independent agents at the same question in isolation, then make them attack each other's findings, then synthesize what survives. Use for research, audits, and any conclusion that must survive scrutiny — the antidote to the first-plausible-answer problem.
---

# Convocation — isolated → adversarial → consensus

The failure this prevents: one agent, one pass, one plausible-sounding answer that nobody checked. The fix is structural, not prompt-level: independent eyes that cannot see each other, then a round where being agreeable is against the rules.

## Round 0 — FRAME (you, 5 minutes)
Write ONE task file all agents will receive identically. Include the question, what a good answer looks like (claims cited to sources/probes, assumptions marked), and the output path convention. State the ground rules: "live probes beat documentation; if you can test it, test it — do not trust docs or memory for anything that can change." Do not include your own hypothesis — that contaminates every agent the same way.

## Round 1 — ISOLATED
Each agent gets the identical task file, a separate working directory, and NO sight of any other agent's output. Diversity of engines beats diversity of prompts: different vendors (claude / codex / qwen) fail differently, which is the point. Headless one-shots:

    /opt/homebrew/bin/claude -p "$(cat TASK.md)" > out/claude.md
    /opt/homebrew/bin/codex exec "$(cat TASK.md)" > out/codex.md
    /opt/homebrew/bin/qwen -p "$(cat TASK.md)" > out/qwen.md

(Full binary paths on purpose — bare names break from launchd/cron/ssh contexts. The runner: /Users/jonathan/svnCheckouts/js-db-ad-astra/tools/convocation/panel, binaries overridable via CLAUDE_BIN/CODEX_BIN/QWEN_BIN.)

(The runner at /Users/jonathan/svnCheckouts/js-db-ad-astra/tools/convocation/panel does this round for you.) Resist the urge to peek and steer mid-round — a steered agent is a copy of you.

## Round 2 — ADVERSARIAL
Each agent receives the OTHER agents' round-1 outputs with instructions to attack, not review: "Find what is WRONG. Fact-check every checkable claim with a live probe. Being polite about an error is a failure. Produce corrections with receipts." Feed A's output to B and C, B's to A and C, etc. Same headless mechanics, new task file per agent.

What this catches (live examples from the 8/6 Fable+Sol run): a hallucinated 381k-star count (actual: 16), a retired model recommended as current (410'd on live probe), a wrong billing claim, a stale hooks claim. Round 1 asserted all four confidently; round 2 killed them.

## Round 3 — CONSENSUS
One adjudicator (you, or a fresh agent) merges:
- Keep claims that survived attack; carry their receipts.
- Record every correction in a **fact-check scorecard** ("Sol corrected Fable: X; Fable corrected Sol: Y"). The scorecard is the evidence the process worked. It also tells you which agent to trust on which axis next time.
- Where agents still disagree, don't split the difference: name the disagreement, state what probe would settle it, and either run the probe or mark it open.
- Occam picks among survivors. Unverifiable claims ship as marked assumptions or not at all.

Deliverable: one SYNTHESIS doc + the scorecard. The synthesis note in Apple Notes / the repo is the living copy.

## Cross-fix variant (for prose and design artifacts)
When the convocation targets an editable artifact (a document, a design, a config) rather than a codebase, replace round 2 with a cross-fix round. Model A's findings go to model B for fixing. Model B's findings go to model A. The original finder then approves or rejects each fix. The fixer has to understand the finding deeply enough to apply it, and the finder holds real veto power over fixes that changed meaning or missed the point. The cross-fix is the cross-brand verification — a different architecture both interprets and corrects the finding. Triage before cross-fixing: not every finding is worth a fix. Pick the ones that change how a reader understands the document. Leave marginal style preferences on the floor.

## When to panel vs when not
Convene a panel: research with checkable claims, audits, design reviews, anything feeding a purchase or an architecture decision. Don't panel: mechanical tasks, pure preference calls, or anything where one live probe answers the question outright — run the probe instead.

## Cost shape
Three agents × two rounds ≈ 6 headless runs. Cheap models are fine for round 1 breadth; put the strongest model on round 2 attacks and the adjudication.
