#!/usr/bin/env zsh
set -euo pipefail
# hook-subtract.sh — REMOVE this kit's managed pre-commit block from the enclosing repo,
# preserving any other hook content (the exact inverse of setup.sh). Backs up first.
# Usage: tools/pdf-sidecars/hook-subtract.sh
emit() { print -r -- "$@" }
die()  { print -r -- "subtract: $*" >&2; exit 1 }
KIT_DIR="${0:A:h}"
SUPER="$(git -C "$KIT_DIR/.." rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repo"
HOOKS_DIR="$(git -C "$SUPER" rev-parse --git-path hooks)"; [[ "$HOOKS_DIR" = /* ]] || HOOKS_DIR="$SUPER/$HOOKS_DIR"
HOOK="$HOOKS_DIR/pre-commit"
BEGIN="# >>> pdf-sidecars pre-commit (managed by pdf-sidecars/setup.sh) >>>"
END="# <<< pdf-sidecars pre-commit <<<"
[[ -f "$HOOK" ]] || { emit "no pre-commit hook — nothing to remove"; exit 0 }
if ! grep -qF "$BEGIN" "$HOOK"; then emit "no pdf-sidecars managed block in hook — nothing to remove"; exit 0; fi
bak="$HOOK.bak.$(date +%Y%m%d-%H%M%S)"; cp -p "$HOOK" "$bak"; emit "→ backed up → ${bak##*/}"
awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip{print}' "$HOOK" > "$HOOK.tmp" && mv "$HOOK.tmp" "$HOOK"
chmod +x "$HOOK"
# if only a bare shebang / whitespace remains, remove the empty hook entirely
if ! grep -qvE '^\s*(#!.*)?\s*$' "$HOOK"; then rm -f "$HOOK"; emit "→ hook was now empty — removed it"; else emit "→ removed pdf-sidecars block, other hook content preserved"; fi
git -C "$SUPER" config --unset jsutils.path 2>/dev/null || true
emit "✓ unwired pdf-sidecars from this repo."
