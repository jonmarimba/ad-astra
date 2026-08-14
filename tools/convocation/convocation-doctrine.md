# Convocation doctrine — convoq-first, mix models AND brands

A "convocation" is a multi-agent review/panel — a per-tool bug hunt, a design panel, an adversarial-verify round. Two hard requirements, both load-bearing:

**1. Convoq-first, every round.** Before firing a convocation on a tool or subsystem, search convoq for the known bugs, edge cases, and past decisions already hit on that exact tool, and feed those into the reviewers' prompts so they start from what is already known instead of re-deriving it from zero. We forget; the record does not. A convocation that rediscovers what convoq already holds burned the run for nothing.

```
cd ~/svnCheckouts/js-llmKicker/contrib/authsec-bridge
PYTHONPATH=src python3 -m session_bridge.convoq.cli update
PYTHONPATH=src python3 -m session_bridge.convoq.cli search '<tool name / bug term>' --kind human
```

**2. Mix models AND brands — a same-brand panel is an echo chamber wearing a quorum's clothes.** The panel must span multiple model *brands*, not N copies of one model. Independent architectures fail differently, so brand diversity is the whole point — it is what makes the panel catch what one model's blind spots would silently pass. Route review slices and verifiers across brands deliberately, and state which brand ran which slice so the diversity is auditable, not assumed. Proven local brands:

- **Claude** — this harness (Agent / Workflow subagents).
- **Codex / GPT** — `codex exec --sandbox read-only '<prompt>'` (headless, authed).
- **Qwen CLI → omniroute → hot cloud models** — `qwen -m <model> -p '<prompt>'`, where `<model>` is an omniroute id (e.g. `hf/moonshotai/Kimi-K2.7-Code`, `hf/deepseek-ai/DeepSeek-V4-Pro`, `hf/zai-org/GLM-5.2`). List available: `curl -s http://localhost:20128/v1/models`. A raw `ollama/<model>` or `auto/<x>` will 404 — use the exact `hf/…` id.

Prefer cross-brand verification too: have one brand adversarially verify another brand's findings, so a confirmed defect survived a *different* architecture, not the same one that raised it.
