**Dead code and duplicate code detection (swift and others)**

@ghost **2026-08-18 JS:** remind me tomorrow evening to go over tech to try. Maybe place it in notes (here) instead of having it be a sidecar in Obsidian I never look at because it’s kind of locked on my computer. Obsidian is a “let’s try this” tech. Notes is an “I use this” tech.

—————————————————————————————————————————

peripheryapp/periphery: A tool to identify unused code in ...GitHubhttps://github.com › peripheryapp › periphery

Vs PMD

Specifically, I need dead and duplicate code detection for swift, but also, maybe would need one for python or other??

I’d love to be able to find a tool that doesn’t just look for copy-pasta, but one that figures out how two places do the same kind of thing with similar system APIs

Like, imagine if multiple parts of an app write to the camera roll (I know we don’t call it that anymore) in a particular way that’s tailored to the app and maybe somebody write that to an early spec and then somebody else didn’t notice it was already done in one way elsewhere and then rewrote it in a different part of the app.

@ghost

**GhOST reply, 2026-08-06 11:46:**

Periphery vs PMD — they're complementary, not competitors, and answer different halves of your question: Periphery is the real, gold-standard Swift-specific dead-code detector — analyzes Xcode projects/SPM packages, finds unused declarations (variables, functions, whole classes) more thoroughly than Xcode's own warnings.

This is your dead-code tool for Swift, full stop. PMD supports Swift with only 4 rules — not useful for Swift specifically. Its actual strength is CPD (Copy-Paste Detector), which works across many languages via tokenization — good for literal copy-paste duplication, not Swift-aware beyond that. So:

Periphery for dead code, PMD/CPD only if you need cross-language copy-paste detection (e.g. flagging duplicated logic between your Python tooling and something else). On the harder ask — finding two places that do the SAME KIND OF THING via similar system APIs but implemented differently (your camera-roll example):

this is &quotsemantic clone detection" (specifically Type-3/Type-4 clones in the literature), and it's genuinely a research-frontier problem, not a solved one with a mature off-the-shelf CLI tool.

Current academic approaches (DeepSim, TBCCD, SLACC, graph/AST-based methods with Siamese neural architectures) exist but aren't packaged as something you'd `brew install` and point at a Swift codebase today — they're mostly research prototypes evaluated on academic benchmarks (BigCloneBench), and a recent 2026 survey (&quotSemantic Code Clone Detection:

Are We There Yet?") suggests the honest answer is no, not reliably. Practical path given that gap: this is actually a good fit for an LLM-driven review pass rather than a static-analysis tool — explicitly prompt an agent to scan for &quotdifferent code, same underlying intent/API usage pattern" rather than textual similarity.

That's exactly the kind of judgment call static analyzers are bad at and LLMs are decent at. Worth trying as a one-off agent task on a real codebase (maybe one of the MHM apps) before assuming you need to build or adopt a specialized tool.

@ghost - stick a brief synthesis of this analysis linking to the tool including your manual suggestion in the tech to try file

**GhOST reply, 2026-08-18:**

Researched, and the verdict is in the canonical tech-to-try list in @astra, symlinked into Obsidian as *tech-to-try.md*. Replying here because the work landed but the note was never marked answered.

The synthesis is filed with the manual suggestion you asked for: **Periphery** for Swift dead code, which is the gold standard; **PMD/CPD** for cross-language copy-paste; and an **LLM semantic-clone pass** for Type-3 and Type-4 clones, where no mature CLI exists and the practical approach is prompting an agent for “same intent, different implementation”. Recommended trial target is one of the Maharam apps.