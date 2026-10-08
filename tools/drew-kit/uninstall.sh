#!/usr/bin/env bash
# uninstall.sh — the uniform entry point: `uninstall.sh --into <repo>`. Delegates to
# uninstall-from-repo.sh, which removes the managed import block and whatever the install method
# dropped in (.drew-kit/ or .drew-kit-src/) and touches nothing else.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=""; want_into=0
for a in "$@"; do
  if [ "$want_into" = 1 ]; then REPO="$a"; want_into=0; continue; fi
  [ "$a" = "--into" ] && want_into=1
done
[ -n "$REPO" ] || { echo "usage: uninstall.sh --into <repo>" >&2; exit 64; }
exec "$HERE/uninstall-from-repo.sh" "$REPO"
