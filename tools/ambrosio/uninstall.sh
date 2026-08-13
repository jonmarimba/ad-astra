#!/usr/bin/env bash
# uninstall.sh — dis-integrate ambrosio: remove its state dir (~/.ambrosio: config, seen.txt, logs).
# Deps are curl + python@3.12 — foundational runtimes shared by the whole system, never auto-removed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "ambrosio dis-integrate:"
uc_rm_state "${AMBROSIO_HOME:-$HOME/.ambrosio}" "ambrosio state dir (config/seen/logs)"
uc_keep curl "system HTTP client"
uc_keep "python@3.12" "foundational Python runtime"
echo "done."
