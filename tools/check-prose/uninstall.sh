#!/usr/bin/env bash
# check-prose — uninstall the prose checker into a given repo.
#
# Installs check-prose.js AND rules.json together. The rules are DATA and travel
# with the tool, so the astra registry keeps every repo's copy current — which is
# the whole point: the previous version had its word list hardcoded in one repo's
# JS, drifting from the skill and from Jonathan's own CLAUDE.md.
#
# A repo may extend without forking by adding .check-prose.json at its root.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: uninstall.sh --into <repo>" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "no such directory: $TARGET" >&2; exit 66; }
TARGET="$(cd "$TARGET" && pwd -P)"
case "$TARGET" in
  "$HOME"|"$HOME/.claude"*|"$HOME/.agents"*|"$HOME/.config"*|"$HOME/Library"*)
    echo "REFUSING: $TARGET is a home/global location." >&2; exit 78 ;;
esac
D="$TARGET/tools"
if [ "uninstall" = "install" ]; then
  mkdir -p "$D"
  cp "$HERE/check-prose.js" "$HERE/rules.json" "$D/"
  echo "installed check-prose.js + rules.json -> $D"
else
  rm -f "$D/check-prose.js" "$D/rules.json"
  echo "removed check-prose.js + rules.json from $D"
fi
exit 0
