#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
command -v brew >/dev/null && brew bundle --file="$HERE/Brewfile" || echo "ensure 'imsg' is installed"
"$HERE/botline" list >/dev/null 2>&1 || true   # materialize default config
echo "botline ready. Config: ~/.botline/config (edit JS_NUMBER / JS_CHAT_ID for a different recipient)."
echo "Run the dispatcher on a timer so replies route, e.g.:  */2 * * * *  $HERE/botline dispatch"
