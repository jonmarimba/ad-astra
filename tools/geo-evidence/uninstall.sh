#!/usr/bin/env bash
# uninstall.sh — dis-integrate geo-evidence: remove its config/state dir (~/.geo-evidence, which
# holds YOUR property coordinates), and OPTIONALLY (--deps) the shared deps exiftool + osxphotos.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
GEO_HOME="${GEO_EVIDENCE_HOME:-$HOME/.geo-evidence}"
echo "geo-evidence dis-integrate:"
[ -f "$GEO_HOME/config" ] && uc_warn "about to remove your geo-evidence config (property coordinates):" "$GEO_HOME/config" "Copy it first if you want to keep those coordinates."
uc_rm_state "$GEO_HOME" "geo-evidence config/state dir"
uc_brew exiftool "exiftool reads/writes EXIF for many photo workflows"
uc_uv_tool osxphotos "osxphotos queries/exports your Photos library"
echo "done."
