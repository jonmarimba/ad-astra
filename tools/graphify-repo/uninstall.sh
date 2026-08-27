#!/usr/bin/env bash
# uninstall.sh — remove graphify-repo from a repo.
#
# Removes only what install.sh placed. It does NOT delete graphify-out/, because
# that is generated output that may represent a long run over a large tree, and
# a tool that silently discards work while uninstalling itself is the same
# mistake as one that overwrites a file while installing itself. Remove it by
# hand if you want it gone.
#
# The .git/info/exclude line is also left alone: it is one comment-free line
# naming a directory that may still exist, and rewriting another repo's git
# config to tidy up is more risk than the tidiness is worth.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/astra-install.sh"

# uninstall-common gives --deps its meaning and its loud banners. Without it this uninstaller
# removed the repo-side install and left `graphifyy` (installed by install.sh via `uv tool
# install`) and the vault symlink dir behind, with no way to ask for them — the only tool in
# the sweep whose --deps did nothing at all.
. "$HERE/../lib/uninstall-common.sh"

# astra_target owns --into; uc_parse owns --deps, and each rejects the other's flags with
# exit 64. Rather than teach either parser about the other tool's vocabulary, hand each one
# only what it understands. An unknown flag still reaches uc_parse and is still refused,
# which is what the sweep's red control checks.
astra_target "$@"
uc_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --into) shift 2 || shift ;;
    --into=*) shift ;;
    *) uc_args+=("$1"); shift ;;
  esac
done
# bash 3.2: an empty array under set -u is an unbound variable, not an empty list.
uc_parse ${uc_args[@]+"${uc_args[@]}"}
astra_remove graphify-repo

# The vault holds SYMLINKS into repos' graphify-out, not the reports themselves, so removing
# it destroys no analysis — the generated output stays where it was produced.
uc_rm_state "${GRAPHIFY_VAULT:-$HOME/.notesq/vault/graphify}" "graphify vault (symlinks to per-repo reports)"
uc_uv_tool graphifyy "the graphify CLI itself; other repos' installs of graphify-repo need it"

if [ -d "$TARGET/graphify-out" ]; then
  echo "note: $TARGET/graphify-out still holds generated graph output — left in place deliberately."
fi
