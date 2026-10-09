#!/usr/bin/env bash
# astra-scope: repo
# install.sh — usage-meters: context, token and subscription-limit meters around the
# prompt of Claude Code, Qwen Code and Codex, for sessions started in one repo.
#
# Claude Code: the status line below the prompt shows the current folder and the 5-hour
# and 7-day subscription limits as bars with reset times. The astra-usage-meters plugin
# above the prompt shows the context length and the non-cache-read tokens used today
# and in the last hour. The plugin lands in .claude/skills/, which Claude Code loads
# with no install step once the folder is trusted.
# Qwen Code: the status line shows the current folder, the context length and this
# session's non-cache-read tokens. Qwen Code reports no subscription limits.
# Codex: the status line shows Codex's own items for the project, context, the 5-hour
# and weekly limits and used tokens, because Codex cannot run a status-line command.
#
# Every file is recorded in .astra/manifest.json and kept current by the repo's
# post-commit hook. The config entries are listed in settings-entries.json. Nothing
# is written outside the repo.
#
# Requires jq (status lines) and /usr/bin/python3 (plugin) on the machine that runs the agents.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
P=tools/usage-meters/claude-plugin
S=.claude/skills/astra-usage-meters
astra_place_at usage-meters \
  "tools/usage-meters/statusline.sh:.astra/usage-meters/statusline.sh" \
  "tools/usage-meters/statusline-qwen.sh:.astra/usage-meters/statusline-qwen.sh" \
  "$P/.claude-plugin/plugin.json:$S/.claude-plugin/plugin.json" \
  "$P/hooks/hooks.json:$S/hooks/hooks.json" \
  "$P/hooks/register.tsx:$S/hooks/register.tsx" \
  "$P/bin/tally_tokens.py:$S/bin/tally_tokens.py" \
  "$P/types/index.d.ts:$S/types/index.d.ts" \
  "--settings=tools/usage-meters/settings-entries.json"
command -v jq >/dev/null 2>&1 || echo "usage-meters: jq is not installed; the status lines need it (brew install jq)" >&2
