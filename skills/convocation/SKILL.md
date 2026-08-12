---
name: convocation
description: Run N independent agents at the same question in isolation, then make them attack each other's findings, then synthesize what survives. Use for research, audits, and any conclusion that must survive scrutiny — the antidote to the first-plausible-answer problem.
---

# Convocation — isolated → adversarial → consensus

The failure this prevents: one agent, one pass, one plausible-sounding answer that nobody checked. The fix is structural, not prompt-level: independent eyes that cannot see each other, then a round where being agreeable is against the rules.

## Round 0 — FRAME (you, 5 minutes)
Write ONE task file all agents will receive identically. It contains: the question; what a good answer looks like (claims cited to sources/probes, assumptions marked); the ground rules ("live probes beat documentation; if you can test it, test it — do not trust docs or memory for anything that can change"); and the output path convention. Do not include your own hypothesis — that contaminates every agent the same way.

## Round 1 — ISOLATED
Each agent gets the identical task file, a separate working directory, and NO sight of any other agent's output. Diversity of engines beats diversity of prompts: different vendors (claude / codex / qwen) fail differently, which is the point. Headless one-shots:

    claude -p "$(cat TASK.md)" > out/claude.md
    codex exec "$(cat TASK.md)" > out/codex.md
    qwen -p "$(cat TASK.md)" > out/qwen.md

(The `convoke` tool in ../tools/convocation runs this round for you.) Resist the urge to peek and steer mid-round — a steered agent is a copy of you.

## Round 2 — ADVERSARIAL
Each agent receives the OTHER agents' round-1 outputs with instructions to attack, not review: "Find what is WRONG. Fact-check every checkable claim with a live probe. Being polite about an error is a failure. Produce corrections with receipts." Feed A's output to B and C, B's to A and C, etc. Same headless mechanics, new task file per agent.

What this catches (live examples from the 8/6 Fable+Sol run): a hallucinated 381k-star count (actual: 16), a retired model recommended as current (410'd on live probe), a wrong billing claim, a stale hooks claim. Round 1 asserted all four confidently; round 2 killed them.

## Round 3 — CONSENSUS
One adjudicator (you, or a fresh agent) merges:
- Keep claims that survived attack; carry their receipts.
- Record every correction in a **fact-check scorecard** ("Sol corrected Fable: X; Fable corrected Sol: Y") — the scorecard IS the evidence the process worked, and it tells you which agent to trust on which axis next time.
- Where agents still disagree, don't split the difference: name the disagreement, state what probe would settle it, and either run the probe or mark it open.
- Occam picks among survivors. Unverifiable claims ship as marked assumptions or not at all.

Deliverable: one SYNTHESIS doc + the scorecard. The synthesis note in Apple Notes / the repo is the living copy.

## When to convoke vs when not
Convoke: research with checkable claims, audits, design reviews, anything feeding a purchase or an architecture decision. Don't convoke: mechanical tasks, matters of taste, anything where one live probe answers the question outright — run the probe instead.

## Cost shape
Three agents × two rounds ≈ 6 headless runs. Cheap models are fine for round 1 breadth; put the strongest model on round 2 attacks and the adjudication.
