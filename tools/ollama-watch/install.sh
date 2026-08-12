#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/ollama-watch" check >/dev/null 2>&1 || true   # seed
echo "ollama-watch seeded. Add a daily timer:  0 9 * * *  $HERE/ollama-watch check"
