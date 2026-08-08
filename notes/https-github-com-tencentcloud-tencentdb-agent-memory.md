https://github.com/TencentCloud/TencentDB-Agent-Memory

@ghost useful beside convoq? Anything else like this out there? Looks a little bit graphify shaped

***GhOST reply, 2026-08-03 13:31:***

*Dug deeper (multiple independent sources, not just their own repo): TencentDB Agent Memory hit #1 GitHub Trending 7/8/26, covered independently by MarkTechPost and a Medium tester who ran real numbers — 61% token reduction and PersonaMem accuracy 48%→76% when paired with OpenClaw, not just marketing claims. It's a 4-tier LOCAL memory pipeline, zero external API deps, built around a 'Memory Hub' that governs/shares 4 asset types (Chat Memory, Skill, LLM-Wiki, Code-Graph) across a TEAM of agents — that team-sharing angle is the actual differentiator vs. convoq, which is session-transcript search/distillation for one user, not a governed multi-agent memory bank. Landscape check: Mem0 (drop-in personalization), Zep/Graphiti (temporal 'who owned what when' reasoning), Letta/MemGPT (self-editing OS-level memory), LangMem (LangGraph-native) all solve different slices — none do the team-governance thing TencentDB does. Your graphify instinct was right: found a real GitHub issue (safishamsi/graphify #152) proposing exactly this pairing — graphify maps codebase STRUCTURE, agent-memory tools like this track developer DECISIONS/patterns across sessions. Complementary, not competing. Given kicker's whole shared-crew-memory problem, this is closer to what you actually need than convoq alone.*

@ghost add to tech to try

***GhOST reply, 2026-08-03 21:52:***

*Already added — TencentDB Agent Memory is in todo/tech-to-try.md from the research pass earlier today.*

@astra