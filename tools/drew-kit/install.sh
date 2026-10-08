#!/usr/bin/env bash
# astra-scope: repo-config
# install.sh — the uniform entry point for drew-kit: `install.sh --into <repo> [options]`.
# Everything after --into <repo> passes through to install-into-repo.sh, which owns the logic and
# keeps its own positional form (`install-into-repo.sh <repo> [--set ..] [--method ..]`), so both
# spellings work and neither can drift from the other.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=""; REST=(); want_into=0
for a in "$@"; do
  if [ "$want_into" = 1 ]; then REPO="$a"; want_into=0; continue; fi
  if [ "$a" = "--into" ]; then want_into=1; continue; fi
  REST+=("$a")
done
[ -n "$REPO" ] || { echo "usage: install.sh --into <repo> [--set swift|jira|all] [--method copy|submodule|subtree|subtree-split] ..." >&2; exit 64; }
exec "$HERE/install-into-repo.sh" "$REPO" ${REST[@]+"${REST[@]}"}
