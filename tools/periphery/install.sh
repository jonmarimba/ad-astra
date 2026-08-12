#!/usr/bin/env bash
# install.sh — periphery (Swift dead-code scanner). Which-first: never a second copy.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
if p="$(command -v periphery 2>/dev/null)"; then
  echo "already installed: periphery -> $p $( [ -L "$p" ] && echo "-> $(readlink "$p")" )"
else
  brew bundle --file="$HERE/Brewfile"
fi
periphery version
