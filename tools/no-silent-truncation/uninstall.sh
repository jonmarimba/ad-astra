#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — remove the no-silent-truncation guard, its hook entry and its watchlist.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/astra-install.sh"
astra_target "$@"
rm -f "$TARGET/.astra/no-silent-truncation/no-silent-truncation.watchlist"
astra_remove no-silent-truncation
