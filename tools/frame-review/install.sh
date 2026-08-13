#!/usr/bin/env bash
# install.sh — frame-review needs only ffmpeg. Which-first: never a second copy.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
if p="$(command -v ffmpeg 2>/dev/null)"; then
  echo "already installed: ffmpeg -> $p"
else
  brew bundle --file="$HERE/Brewfile"
fi
echo "frame-review ready: $HERE/frame-review <video> [--fps 0.5] [--outdir DIR]"
exit 0
