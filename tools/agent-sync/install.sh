#!/usr/bin/env bash
# astra-scope: machine
# install.sh — agent-sync on this Mac: Homebrew rsync 3.x (zstd on the wire;
# macOS ships openrsync, zlib only) and uv, the session-bridge submodule, and a
# launchd agent that runs "agent-sync scheduled" every hour to pull the peer's
# sessions into this Mac. Run it on EACH Mac you sync: either one may be asleep
# or offline, so each pulls on its own and catches up when the other is back.
# It installs nothing into a repo.
#
#   install.sh                 dependencies + hourly schedule
#   install.sh --interval N    schedule every N minutes instead
#   install.sh --no-schedule   dependencies only (and removes a schedule if present)
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL=astra.agent-sync
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/agent-sync"
interval=60 schedule=1
while [ $# -gt 0 ]; do case "$1" in
  --interval) interval="${2:?minutes}"; shift 2 ;;
  --no-schedule) schedule=0; shift ;;
  *) echo "install.sh: unknown argument $1" >&2; exit 64 ;;
esac; done

brew bundle --quiet --file="$HERE/Brewfile"
git -C "$HERE/../.." submodule update --init vendor/authsec-bridge
"$(brew --prefix)/bin/rsync" --version | grep -q zstd || { echo "agent-sync: rsync lacks zstd" >&2; exit 1; }

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true   # absent on a first install
rm -f "$PLIST"
if [ "$schedule" = 1 ]; then
  mkdir -p "$(dirname "$PLIST")" "$CACHE"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$HERE/agent-sync</string><string>scheduled</string></array>
  <key>StartInterval</key><integer>$((interval * 60))</integer>
  <key>RunAtLoad</key><false/>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>StandardOutPath</key><string>$CACHE/launchd.log</string>
  <key>StandardErrorPath</key><string>$CACHE/launchd.log</string>
</dict>
</plist>
PL
  plutil -lint -s "$PLIST"
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "agent-sync: ready; pulls the peer every $interval min (log: $CACHE/scheduled.log)"
else
  echo "agent-sync: ready (rsync with zstd, uv, session-bridge); no schedule"
fi
