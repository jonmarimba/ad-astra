# mcp-bundle — the kicker MCP server set, installed PER REPO

The first astra tool that is a bundle of tools. `setup-mcp.sh` began as a copy of `js-llmKicker/scripts/setup-mcp.sh`. The default now uses the Xcode 27 combined front.

```
./install.sh   --into <repo> [servers...]
./uninstall.sh --into <repo> [servers...]
./setup-mcp.sh --list           # read-only, from inside a repo
```

The default set uses `xcode-combined` with `mac-control-mcp`, `ios-simulator`, `mobile-mcp`, and `kickerd`. Direct Xcode providers remain available by explicit name.

It configures the set for four agents that each store config differently:

| agent | file |
|---|---|
| Claude Code | `<repo>/.mcp.json` via `claude mcp add --scope project` |
| Qwen Code | `<repo>/.qwen/settings.json` |
| Gemini CLI | `<repo>/.gemini/settings.json` |
| Codex CLI | `<repo>/.codex/config.toml` |

## Never global

Every write lands inside the target repo. `setup-mcp.sh` already honoured this — it only ever uses `--scope project` and repo-relative paths. The wrappers now *assert* it: a target under `$HOME`, `~/.claude`, `~/.agents`, `~/.config` or `~/Library` is refused with exit 78. Targets are resolved with `pwd -P` so a symlinked repo (js-speedway is one) resolves to its real path instead of being skipped.

On 2026-08-18 the global installs that had accumulated were removed. They were five skills under `~/.claude/skills` (including astra's own graphify), `~/.agents`, and an `xcode-mcp-server` entry in the Claude Desktop config. Backups were kept in `_removed-globals-20260818/`, removed from the tree on 2026-10-04 and still in history: `git show db36cc8:tools/mcp-bundle/_removed-globals-20260818/<file>`. Restore from there rather than reinstalling globally.

## Where this went

The planned breakup has since happened: the servers now live as small composable astra tools. `tools/lib/templates.json` composes them into per-kind templates, and QUICKSTART.md at the repo root describes them. This bundle stays as the crude first step it was — one bundle, per repo, with a working uninstall.
