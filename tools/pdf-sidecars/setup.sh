#!/usr/bin/env zsh
set -euo pipefail

# setup.sh — wire this pdf-sidecars kit into the enclosing repo, SAFELY.
#
# Records the kit path in `git config jsutils.path` and installs a pre-commit
# hook that regenerates PDF text sidecars for staged PDFs (via hook_pre_commit.sh).
#
# SAFETY (this kit is meant to land in repos that ALREADY have PDF tooling):
#  * The existing pre-commit hook is BACKED UP (timestamped) before ANY change.
#  * If the repo already has its OWN PDF-sidecar hook (a hand-rolled
#    generate_pdf_sidecars.sh call — not this kit's managed block), setup
#    REFUSES by default rather than silently double-installing. Choose:
#       --replace   back up the old hook, install ONLY this kit's managed block
#       --coexist   back up, append this kit's block alongside the old one
#                   (both run; safe — sidecar generation is skip-if-exists and
#                    produces identical output, so the second pass is a no-op)
#  * Re-running on a repo already managed by this kit just refreshes the block.
#
# Usage:  tools/pdf-sidecars/setup.sh [--replace | --coexist]

MODE="guarded"
case "${1:-}" in
  --replace) MODE="replace" ;;
  --coexist|--force) MODE="coexist" ;;
  "" ) ;;
  * ) print -r -- "setup: unknown option '$1' (use --replace or --coexist)" >&2; exit 64 ;;
esac

emit() { print -r -- "$@" }
die()  { print -r -- "setup: $*" >&2; exit 1 }

KIT_DIR="${0:A:h}"
SUPER="$(git -C "$KIT_DIR/.." rev-parse --show-toplevel 2>/dev/null)" \
  || die "not inside a git repo (run me from within the repo you want wired)"

HOOKS_DIR="$(git -C "$SUPER" rev-parse --git-path hooks)"
[[ "$HOOKS_DIR" = /* ]] || HOOKS_DIR="$SUPER/$HOOKS_DIR"
HOOK="$HOOKS_DIR/pre-commit"

BEGIN="# >>> pdf-sidecars pre-commit (managed by pdf-sidecars/setup.sh) >>>"
END="# <<< pdf-sidecars pre-commit <<<"

managed_block() {
  cat <<BLOCK_EOF
$BEGIN
_kit="\$(git config --get jsutils.path 2>/dev/null)"
if [ -n "\$_kit" ] && [ -x "\$_kit/hook_pre_commit.sh" ]; then
    "\$_kit/hook_pre_commit.sh" || exit \$?
fi
$END
BLOCK_EOF
}

backup_hook() {
  [[ -f "$HOOK" ]] || return 0
  local bak="$HOOK.bak.$(date +%Y%m%d-%H%M%S)"
  cp -p "$HOOK" "$bak"
  emit "→ backed up existing hook → ${bak##*/}"
}

# --- classify the current hook ---
has_managed=0; has_foreign_pdf=0
if [[ -f "$HOOK" ]]; then
  grep -qF "$BEGIN" "$HOOK" && has_managed=1
  if [[ $has_managed -eq 0 ]] && grep -qE 'generate_pdf_sidecars|hook_pre_commit\.sh' "$HOOK"; then
    has_foreign_pdf=1
  fi
fi

# --- guard: existing foreign PDF tooling, no explicit mode chosen ---
if [[ $has_foreign_pdf -eq 1 && "$MODE" == "guarded" ]]; then
  emit "⚠ This repo ALREADY has its own PDF-sidecar pre-commit hook:"
  grep -nE 'generate_pdf_sidecars|hook_pre_commit\.sh' "$HOOK" | sed 's/^/      /'
  emit ""
  emit "  Not touching it (no double-install, no changes made). To proceed:"
  emit "    setup.sh --replace   take over: back up the old hook, install only this kit"
  emit "    setup.sh --coexist   keep both: back up, append this kit (safe; skip-if-exists)"
  emit ""
  emit "  jsutils.path was NOT changed."
  exit 2
fi

# record the kit path (safe; a foreign old hook does not read it)
git -C "$SUPER" config jsutils.path "$KIT_DIR"
emit "→ jsutils.path = $KIT_DIR"

mkdir -p "$HOOKS_DIR"

if [[ $has_managed -eq 1 ]]; then
  backup_hook
  # Replace the existing BEGIN..END managed block in place, preserving everything else.
  # Guarded: a missing/misordered marker aborts loudly instead of doing arithmetic on
  # an empty variable (set -u would kill us mid-rewrite) or splicing garbage.
  bstart=$(grep -nF "$BEGIN" "$HOOK" | head -1 | cut -d: -f1) || true
  bend=$(grep -nF "$END" "$HOOK" | head -1 | cut -d: -f1) || true
  if [[ -z "$bstart" || -z "$bend" || "$bend" -le "$bstart" ]]; then
    die "managed block markers missing or out of order in $HOOK (BEGIN@${bstart:-none}, END@${bend:-none}) — hook left untouched; fix by hand or rerun with --replace"
  fi
  { head -n $((bstart - 1)) "$HOOK"; managed_block; tail -n +$((bend + 1)) "$HOOK"; } > "$HOOK.tmp" && mv "$HOOK.tmp" "$HOOK"
  emit "→ refreshed the managed hook block (other content untouched)"
elif [[ "$MODE" == "replace" ]]; then
  backup_hook
  { printf '#!/bin/bash\n\n'; managed_block; } > "$HOOK"
  emit "→ replaced hook with this kit's managed block (old hook backed up)"
elif [[ -f "$HOOK" ]]; then
  backup_hook
  # If the existing hook ends with a top-level `exit`, a blind append would be dead
  # code (it runs after the exit). Insert before the LAST top-level exit so the kit's
  # block actually runs; otherwise append at the end.
  last_exit=$(grep -nE '^exit([[:space:]]|$)' "$HOOK" | tail -1 | cut -d: -f1 || true)
  if [[ -n "$last_exit" ]]; then
    { head -n $((last_exit - 1)) "$HOOK"; echo; managed_block; echo; tail -n +"$last_exit" "$HOOK"; } > "$HOOK.tmp" && mv "$HOOK.tmp" "$HOOK"
    emit "→ inserted this kit's block before the hook's trailing exit"
  else
    { printf '\n'; managed_block; } >> "$HOOK"
    emit "→ appended this kit's block to the existing hook"
  fi
else
  { printf '#!/bin/bash\n\n'; managed_block; } > "$HOOK"
  emit "→ created $HOOK"
fi
chmod +x "$HOOK"

emit ""
emit "✓ wired. Staged PDFs get text sidecars on commit."
emit "  Backfill existing PDFs any time:  $KIT_DIR/update_sidecars.sh"
