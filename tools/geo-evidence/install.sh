#!/usr/bin/env bash
# install.sh — geo-evidence deps: osxphotos (Photos-library query/export) + exiftool. Which-first.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
if p="$(command -v exiftool 2>/dev/null)"; then echo "already installed: exiftool -> $p"; else brew bundle --file="$HERE/Brewfile"; fi
if p="$(command -v osxphotos 2>/dev/null)"; then
  echo "already installed: osxphotos -> $p"
else
  command -v uv >/dev/null || { echo "installing uv…"; curl -LsSf https://astral.sh/uv/install.sh | sh; }
  # osxphotos needs Python 3.10+ (it uses `X | None` union syntax); pin it so uv doesn't grab an
  # older interpreter and produce a binary that crashes on import (seen live: 3.9 -> TypeError).
  uv tool install osxphotos --python 3.12
fi
osxphotos --version >/dev/null 2>&1 && echo "geo-evidence ready: $HERE/geo-evidence scan --since D --until D" || echo "osxphotos install may need a shell restart"
exit 0
