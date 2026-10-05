#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the no-silent-truncation guard on its own: blocks piping a search
# over protected data through head, tail or a sed line range. One PreToolUse/Bash
# hook in this repo's .claude/settings.json. The watchlist is the repo's own,
# seeded once and never overwritten by an update. The kill guard is a separate
# tool (no-killing-other-claudes); claude-safety-hooks installs both.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/astra-install.sh"
astra_target "$@"
D=.astra/no-silent-truncation
# Move off the pre-2026-10-04 install (.claude/hooks + settings.local.json), keeping the watchlist.
python3 "$ASTRA_MANIFEST_PY" migrate-safety-hooks "$TARGET" "$D/no-silent-truncation.watchlist" no-silent-truncation.sh
astra_place_at no-silent-truncation \
  "tools/claude-safety-hooks/no-silent-truncation.sh:$D/no-silent-truncation.sh" \
  "--hook=PreToolUse|Bash|$D/no-silent-truncation.sh"
[ -f "$TARGET/$D/no-silent-truncation.watchlist" ] \
  || cp "$HERE/../claude-safety-hooks/no-silent-truncation.watchlist.default" "$TARGET/$D/no-silent-truncation.watchlist"
