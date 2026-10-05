#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — remove the kill guard and its hook entry.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/astra-install.sh"
astra_target "$@"
rm -f "$TARGET/.astra/no-killing-other-claudes/no-killing-other-claudes.reap-hint"
astra_remove no-killing-other-claudes
