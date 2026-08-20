#!/usr/bin/env bash
# install-doctrine.sh — install a tool's OPERATING DOCTRINE into a target repo's agent-instruction
# files, so a capability travels with the rules for using it (Jonathan, 2026-08-13: "the convocation
# installer should also install instructions into the place you add it to; similar for others").
#
# This is drew-kit's marked-block mechanism generalized: copy the doctrine markdown into
# <repo>/.doctrine/<slug>.md and write a repo-RELATIVE @-import block into CLAUDE.md/AGENTS.md (and
# QWEN.md if present). Repo-relative so it survives clone/move — never an absolute machine path.
# Idempotent: re-running refreshes the block in place instead of duplicating. Broken markers abort
# rather than mangle. Companion uninstall-doctrine.sh removes both the block and the copied file.
#
#   install-doctrine.sh <repo> <doctrine-file.md> --slug <name>
#   uninstall-doctrine.sh <repo> --slug <name>
#
# Only capability+POLICY tools ship a doctrine (convocation's convoq-first/mix-brands, geo-evidence's
# nearest-property rule, the test-truthfulness rules). Pure-mechanism tools do not — forcing a
# doctrine block on a plain utility is just noise.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

REPO=""; DOC=""; SLUG=""
while [ $# -gt 0 ]; do case "$1" in
  --slug) SLUG="$2"; shift 2;;
  --*) echo "unknown flag '$1'" >&2; exit 64;;
  *) if [ -z "$REPO" ]; then REPO="$1"; elif [ -z "$DOC" ]; then DOC="$1"; else echo "too many args" >&2; exit 64; fi; shift;;
esac; done
[ -n "$REPO" ] && [ -n "$DOC" ] && [ -n "$SLUG" ] || { echo "usage: install-doctrine.sh <repo> <doctrine-file.md> --slug <name>" >&2; exit 64; }
[ -d "$REPO" ] || { echo "no such repo: $REPO" >&2; exit 1; }
[ -f "$DOC" ] || { echo "no such doctrine file: $DOC" >&2; exit 1; }
# slug must be a bare name — never a path (guards against ../ escapes in the block/paths)
case "$SLUG" in */*|..*|"") echo "bad --slug '$SLUG' (bare name only)" >&2; exit 64;; esac

BEGIN="# >>> doctrine:$SLUG (managed by install-doctrine.sh) >>>"
END="# <<< doctrine:$SLUG <<<"
DEST=".doctrine/$SLUG.md"

cp "$DOC" "$REPO/$DEST.tmp" 2>/dev/null || { mkdir -p "$REPO/.doctrine"; cp "$DOC" "$REPO/$DEST.tmp"; }
mv "$REPO/$DEST.tmp" "$REPO/$DEST"

wrote=0
for target in "$REPO/CLAUDE.md" "$REPO/AGENTS.md" "$REPO/QWEN.md"; do
  # CLAUDE.md/AGENTS.md always; QWEN.md only if it already exists (don't invent it)
  case "$target" in *QWEN.md) [ -f "$target" ] || continue;; esac
  touch "$target"
  if grep -qF "$BEGIN" "$target"; then
    bs=$(grep -nF "$BEGIN" "$target" | head -1 | cut -d: -f1); be=$(grep -nF "$END" "$target" | head -1 | cut -d: -f1)
    { [ -n "$bs" ] && [ -n "$be" ] && [ "$be" -gt "$bs" ]; } || { echo "markers for '$SLUG' broken in $target — fix by hand" >&2; exit 1; }
    { head -n $((bs-1)) "$target"; tail -n +$((be+1)) "$target"; } > "$target.tmp" && mv "$target.tmp" "$target"
  fi
  { echo ""; echo "$BEGIN"; echo "Operating doctrine for '$SLUG' — read it before using that capability here:"; echo ""
    echo "@$DEST"; echo "$END"; } >> "$target"
  echo "installed doctrine '$SLUG' into $target (@$DEST)"
  wrote=$((wrote+1))
done
[ "$wrote" -gt 0 ] || { echo "no CLAUDE.md/AGENTS.md target written" >&2; exit 1; }
