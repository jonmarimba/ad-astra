# usage-meters plan

This plan replaces the first `claude-usage-meters` tool (commit 8fd5426). That tool asked Claude Code to fetch a plugin from a GitHub marketplace, and it served Claude Code only. The new `usage-meters` tool installs through the normal astra machinery for Claude Code, Codex, and Qwen Code.

## Decisions

Andrew made these decisions on 2026-10-09.

- Astra keeps its own copy of the usage-meters plugin source. Andrew's machine keeps the GitHub plugin `drewster99/claude-usage-meters` at user scope, and astra does not use it.
- Codex gets its built-in status-line items, because Codex cannot run a status-line command. Andrew tests the result in Codex.
- Qwen Code gets a command status line that shows the context size and the session's non-cache-read tokens. Qwen Code receives no subscription-limit data, so it shows no Session or Week bars.

## What each agent gets

| Agent | Repo file | Above the prompt | Below the prompt |
|---|---|---|---|
| Claude Code | `.claude/settings.json`, `.claude/skills/astra-usage-meters/` | Context, NCR tok today, Last hour (plugin) | Folder, Session and Week bars with reset times |
| Qwen Code | `.qwen/settings.json` | nothing | Folder, then Context and NCR tok for the session |
| Codex | `.codex/config.toml` | nothing | Built-in items: context used, 5-hour limit, weekly limit, used tokens |

## How it installs

1. `tools/astra add usage-meters` runs `tools/usage-meters/install.sh --into <repo>`.
2. The installer calls `astra_place_at`. That copies the two status-line scripts to `.astra/usage-meters/` and the plugin to `.claude/skills/astra-usage-meters/`. The manifest records every file, so the post-commit hook keeps them current.
3. The same call passes `--settings=tools/usage-meters/settings-entries.json`. Each entry names a config file, a key path, and a value. `astra_manifest.py` writes the entries into the JSON files and the TOML file, records them, and removes exactly them on uninstall.
4. Claude Code loads a plugin folder under `.claude/skills/` with no install step after the user trusts the folder. Nothing is written outside the repo.

## Validation

- `tools/tests/test-usage-meters.sh` installs into fresh repos and into repos with their own settings. It checks every placed file and every config entry in all three files. It also checks reinstalls, kept user edits, refusals of foreign values, and the restore on uninstall.
- The test renders both status-line scripts through the commands written into the config files, with fixed input.
- The plugin's own Python tests run against the copy in astra.
- `test-tool-kinds.sh`, `test-install-contract.sh`, and both test tiers run with an isolated git config. Only failures that also exist without this change may remain.
- A live check starts Claude Code and Qwen Code in an installed repo and reads the screen. Andrew checks Codex.
