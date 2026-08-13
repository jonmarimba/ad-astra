#!/usr/bin/env bash
# uninstall.sh — dis-integrate graphify-repo: remove its vault subdir (~/.notesq/vault/graphify).
# Optional dep: the graphify CLI (uv tool 'graphifyy'). uv itself is foundational, kept.
# NOTE: graphify-out/ dirs inside consumer repos (kicker, pot-mhm) are those repos' to remove.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "graphify-repo dis-integrate:"
uc_rm_state "${GRAPHIFY_VAULT:-$HOME/.notesq/vault/graphify}" "graphify vault output dir"
uc_keep uv "foundational Python tool runner (shared by many tools)"
uc_uv_tool graphifyy "the graphify CLI"
echo "done."
