#!/usr/bin/env bash
# install.sh — place dedup-scan into a repo's .astra, the standard astra_place pattern.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
export ASTRA_ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
. "$ASTRA_ROOT/tools/lib/astra-install.sh"
astra_target "$@"
astra_place dedup-scan dedup-scan
chmod +x "$TARGET/.astra/dedup-scan/dedup-scan"
