#!/usr/bin/env bash
# astra-scope: machine
# uninstall.sh — remove agent-sync's schedule and local cache: the launchd agent,
# the mirrors of other Macs, the Codex database backups and the logs. Homebrew
# rsync and uv stay; other tools use them.
set -euo pipefail
launchctl bootout "gui/$(id -u)/astra.agent-sync" 2>/dev/null || true   # absent if never scheduled
rm -f "$HOME/Library/LaunchAgents/astra.agent-sync.plist"
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/agent-sync"
echo "agent-sync: schedule and cache removed. Homebrew rsync and uv were left installed."
