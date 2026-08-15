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
- **Qwen CLI → omniroute → ollama cloud models** — `qwen -m <model> -p '<prompt>'`, where `<model>` uses the `ollamacloud/` prefix (e.g. `ollamacloud/glm-5.2`, `ollamacloud/kimi-k2.7-code`, `ollamacloud/deepseek-v4-pro:preview`). Do NOT use `hf/...` IDs — those route to the HuggingFace provider, which is a different upstream and will fail. List available ollama cloud models: `curl -s http://localhost:20128/v1/models | jq -r '.data[].id' | grep '^ollamacloud/'`. Jonathan pays $100/month for Ollama Max — use it.

Prefer cross-brand verification too: have one brand adversarially verify another brand's findings, so a confirmed defect survived a *different* architecture, not the same one that raised it.
