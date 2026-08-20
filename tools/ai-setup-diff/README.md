# ai-setup-diff

Read-only comparison of the AI/CLI setup between two Macs over Tailscale — which configs differ, which exist on only one side, hooks/skills drift, brew formula drift. Changes nothing; it exists so the M4↔M5 sync session starts from facts.

```sh
ai-setup-diff                 # vs the M5 (default)
ai-setup-diff other-host      # vs anything on the tailnet
```
Compares: ~/.claude (settings/CLAUDE.md/hooks/skills), ~/.codex, ~/.qwen, opencode.jsonc, brew formulae. Self-gates when the remote is asleep.

Status: built + quoting-bug fixed 8/12; first full verified run pending an awake M5 (first attempt caught one real early signal — the M5 has no `~/.claude/skills/` while the M4 carries six). Feeds Thursday's sync task.
