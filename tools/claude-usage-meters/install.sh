#!/usr/bin/env bash
# astra-scope: repo
# install.sh — claude-usage-meters: usage meters around a Claude Code prompt, for sessions in one repo.
#
# Below the prompt, the status line shows the current folder and the 5-hour session and
# 7-day weekly subscription limits as bars, with the percent left and the reset time.
# Above the prompt, the usage-meters plugin shows the context length and the
# non-cache-read tokens used today and in the last hour.
#
# The status-line script lands in <repo>/.astra/claude-usage-meters/ and stays current
# through the repo's post-commit hook. Three entries go into <repo>/.claude/settings.json:
# the statusLine, the plugin's marketplace (github drewster99/claude-usage-meters), and
# the plugin's enable flag. Claude Code fetches the plugin itself, fresh from GitHub,
# when someone trusts the repo folder. Nothing is written outside the repo.
#
# Requires jq (status line) and /usr/bin/python3 (plugin) on the machine that runs Claude Code.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_place_at claude-usage-meters \
  "tools/claude-usage-meters/statusline.sh:.astra/claude-usage-meters/statusline.sh" \
  "--settings=tools/claude-usage-meters/settings-entries.json"
command -v jq >/dev/null 2>&1 || echo "claude-usage-meters: jq is not installed; the status line needs it (brew install jq)" >&2
echo "claude-usage-meters: start Claude Code in $TARGET and accept the usage-meters plugin when it asks."
