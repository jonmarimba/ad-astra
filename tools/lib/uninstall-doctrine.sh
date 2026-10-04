#!/usr/bin/env bash
# uninstall-doctrine.sh — remove a doctrine block (installed by install-doctrine.sh) from a repo's
# CLAUDE.md/AGENTS.md/QWEN.md and delete the copied .doctrine/<slug>.md. Touches nothing else.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
REPO=""; SLUG=""
while [ $# -gt 0 ]; do case "$1" in
  --slug) SLUG="$2"; shift 2;;
  --*) echo "unknown flag '$1'" >&2; exit 64;;
  *) [ -z "$REPO" ] && REPO="$1" || { echo "one repo only" >&2; exit 64; }; shift;;
esac; done
[ -n "$REPO" ] && [ -n "$SLUG" ] || { echo "usage: uninstall-doctrine.sh <repo> --slug <name>" >&2; exit 64; }
case "$SLUG" in */*|..*|"") echo "bad --slug '$SLUG'" >&2; exit 64;; esac

BEGIN="# >>> doctrine:$SLUG (managed by install-doctrine.sh) >>>"
END="# <<< doctrine:$SLUG <<<"
for target in "$REPO/CLAUDE.md" "$REPO/AGENTS.md" "$REPO/QWEN.md"; do
  [ -f "$target" ] || continue
  grep -qF "$BEGIN" "$target" || continue
  bs=$(grep -nF "$BEGIN" "$target" | head -1 | cut -d: -f1); be=$(grep -nF "$END" "$target" | head -1 | cut -d: -f1)
  { [ -n "$bs" ] && [ -n "$be" ] && [ "$be" -gt "$bs" ]; } || { echo "markers for '$SLUG' broken in $target" >&2; exit 1; }
  { head -n $((bs-1)) "$target"; tail -n +$((be+1)) "$target"; } > "$target.tmp" && mv "$target.tmp" "$target"
  echo "removed doctrine '$SLUG' block from $target"
done
# Drop the file AND its manifest entry. Deleting only the file left an entry
# behind, so every later update reported the doctrine MISSING.
ASTRA_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ASTRA_ROOT/tools/lib/astra_manifest.py" unplace "$REPO" "doctrine-$SLUG"
[ -f "$REPO/.doctrine/$SLUG.md" ] && { rm -f "$REPO/.doctrine/$SLUG.md"; echo "removed $REPO/.doctrine/$SLUG.md"; } || true
rmdir "$REPO/.doctrine" 2>/dev/null || true
python3 "$ASTRA_ROOT/tools/lib/astra_manifest.py" finish "$REPO"
