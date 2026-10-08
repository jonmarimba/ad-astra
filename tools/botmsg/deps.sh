#!/usr/bin/env bash
# deps.sh — the machine half of botmsg: its Brewfile.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v brew >/dev/null || { echo "botmsg: FAIL: brew missing" >&2; exit 69; }
brew bundle --file="$HERE/Brewfile"
