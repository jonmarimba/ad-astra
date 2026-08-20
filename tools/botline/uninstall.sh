#!/usr/bin/env bash
# uninstall.sh — dis-integrate botline: remove its state dir (~/.botline: config, inbox/, watermarks).
# Optional dep: imsg (steipete/tap). NOTE imsg is the shared iMessage transport other tools use too.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "botline dis-integrate:"
uc_rm_state "${BOTLINE_HOME:-$HOME/.botline}" "botline state dir (config/inbox/watermarks)"
uc_brew imsg "imsg is the shared iMessage/SMS transport — GhOST and other tools send through it"
echo "done."
