#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/ambrosio" status >/dev/null 2>&1 || true   # materialize config
echo "ambrosio ready. Config: ~/.ambrosio/config (HOST/watchlist/size cap)."
echo "On the HOST (M5 / Strix box): ensure 'lms' is on PATH + Tailscale SSH allowed."
echo "Schedule it (it self-gates on host reachability), e.g.:  0 */4 * * *  $HERE/ambrosio check"
