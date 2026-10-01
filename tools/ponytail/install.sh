#!/usr/bin/env bash
# install.sh — template-facing shim for ponytail. Template members are invoked as
# `install.sh --into <repo>` (template.py's contract); the real installer here predates
# that convention and takes a positional path. This adapts, nothing more.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) REPO="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$REPO" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
exec "$HERE/install-into-repo.sh" "$REPO"
