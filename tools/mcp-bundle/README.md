# mcp-bundle — the kicker MCP server set, installed PER REPO

The first astra tool that is really a *bundle* of tools. `setup-mcp.sh` is copied
verbatim from `js-llmKicker/scripts/setup-mcp.sh` — astra-fied as-is, deliberately
not refactored yet.

```
./install.sh   --into <repo> [servers...]
./uninstall.sh --into <repo> [servers...]
./setup-mcp.sh --list           # read-only, from inside a repo
```

Servers: `mac-control-mcp`, `xcode-mcp-server`, `xcode`, `ios-simulator`,
`XcodeBuildMCP`, `mobile-mcp`, `kickerd`.

It configures the same set for three agents that each store config differently:

| agent | file |
|---|---|
| Claude Code | `<repo>/.mcp.json` via `claude mcp add --scope project` |
| Qwen Code | `<repo>/.qwen/settings.json` |
| Codex CLI | `<repo>/.codex/config.toml` |

## Never global

Every write lands inside the target repo. `setup-mcp.sh` already honoured this —
it only ever uses `--scope project` and repo-relative paths — and the wrappers
now *assert* it: a target under `$HOME`, `~/.claude`, `~/.agents`, `~/.config` or
`~/Library` is refused with exit 78. Targets are resolved with `pwd -P` so a
symlinked repo (js-speedway is one) resolves to its real path instead of being
skipped.

On 2026-08-18 the global installs that had accumulated were removed: five skills
under `~/.claude/skills` (including astra's own graphify), `~/.agents`, and an
`xcode-mcp-server` entry in the Claude Desktop config. Backups are in
`_removed-globals-20260818/` — restore from there rather than reinstalling
globally.

## Where this is going

Not built yet, and this file will not pretend otherwise. The plan is to break the
bundle into many small composable tools, then add TEMPLATES that install a set
fit for a kind of project: the Maharam repos want the Swift/iOS group plus the
writing tools, the legal repos want the pdf-to-text group plus the writing tools.
This is the crude first step — one bundle, per repo, with a working uninstall.
