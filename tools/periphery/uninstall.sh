#!/usr/bin/env bash
# uninstall.sh — dis-integrate periphery (Swift dead-code scanner). No state; the only artifact is
# the brew formula from peripheryapp's tap.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "periphery dis-integrate:"
echo "  periphery keeps no global state."
uc_brew periphery "Swift dead-code scanner (peripheryapp/periphery tap)"
echo "done."
