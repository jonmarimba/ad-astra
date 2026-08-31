#!/usr/bin/env bash
# uninstall.sh — remove dedup-scan from a repo's .astra.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
export ASTRA_ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
. "$ASTRA_ROOT/tools/lib/astra-install.sh"
astra_target "$@"
astra_remove dedup-scan
