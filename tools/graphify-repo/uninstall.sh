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

astra_target "$@"
astra_remove graphify-repo

if [ -d "$TARGET/graphify-out" ]; then
  echo "note: $TARGET/graphify-out still holds generated graph output — left in place deliberately."
fi
