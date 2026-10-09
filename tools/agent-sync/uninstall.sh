#!/usr/bin/env bash
# astra-scope: machine
# uninstall.sh — remove agent-sync's schedule and local cache: the launchd agent, AgentSync.app,
# the mirrors of other Macs, the Codex database backups and the logs. The shared software it used,
# Homebrew rsync and uv, stays unless you pass --deps, because other tools use both.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
launchctl bootout "gui/$(id -u)/astra.agent-sync" 2>/dev/null || true   # absent if never scheduled
rm -f "$HOME/Library/LaunchAgents/astra.agent-sync.plist"
rm -rf "$HERE/AgentSync.app" "$HERE/agentsync_launch.sh"
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/agent-sync"
echo "agent-sync: schedule and cache removed."
uc_brew rsync "file copy tool the mirrors use; other tools may call it"
uc_brew uv "Python tool runner; several astra tools use it"
