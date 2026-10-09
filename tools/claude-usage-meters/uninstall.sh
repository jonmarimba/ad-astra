#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — claude-usage-meters, removed from <repo> along with its manifest entry
# and the three .claude/settings.json entries its installer wrote.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_remove claude-usage-meters
