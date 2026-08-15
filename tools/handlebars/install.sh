#!/usr/bin/env bash
# install.sh — deps + .app build for handlebars.
# On Andrew's machine (or any new checkout): run this once, then grant TCC
# domains one at a time via `handlebars.sh` with no arguments to see current state.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"

# 1. brew deps (ffmpeg for mic + camera probes; the other 6 checks use pure macOS tools)
if command -v brew >/dev/null; then
  brew bundle --file="$HERE/Brewfile"
else
  echo "no brew — ensure ffmpeg is on PATH for mic/camera probes (the other 6 work without it)"
fi

# 2. build Handlebars.app via wrap-in-app if it doesn't already exist
APP="$HERE/Handlebars.app"
if [ -d "$APP" ]; then
  echo "Handlebars.app already exists — not rebuilding (that would change its hash and"
  echo "  kill every TCC grant it holds). Delete it manually first if a rebuild is intended."
else
  WRAP="$HERE/../wrap-in-app/wrap-in-app"
  if [ -x "$WRAP" ]; then
    "$WRAP" "$HERE/handlebars.sh" --log "$HERE/handlebars.log" --name Handlebars --outdir "$HERE"
    echo "Handlebars.app built. Grant TCC domains one at a time in System Settings."
  else
    echo "wrap-in-app not found at $WRAP — build the .app manually or clone the full tools/ tree."
  fi
fi

echo ""
echo "Run 'handlebars.sh' with no arguments to see which TCC domains are granted."
echo "Each BLOCKED line tells you which System Settings pane to visit."
