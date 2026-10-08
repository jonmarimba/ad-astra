#!/usr/bin/env bash
# deps.sh — install or upgrade the periphery formula (Swift dead-code scanner).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
brewfile_upgrade "$HERE/Brewfile"
