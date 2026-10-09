#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — remove pdf-sidecars from a repo: its pre-commit block, its
# .astra/pdf-sidecars files and its manifest entry. Shared machine deps (brew,
# uv) are kept unless --deps is given, because other tools use them.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
if [ -n "$UC_REPO" ]; then
  . "$HERE/../lib/astra-install.sh"
  astra_target --into "$UC_REPO"
  HOOKS="$(git -C "$TARGET" rev-parse --git-path hooks)"
  [ "${HOOKS#/}" != "$HOOKS" ] || HOOKS="$TARGET/$HOOKS"
  HOOK="$HOOKS/pre-commit"
  if [ -f "$HOOK" ]; then
    # Both markers: the current one, and the one setup.sh wrote before the
    # installer took over (hook-subtract.sh only ever knew the old one).
    awk '
      $0=="# >>> pdf-sidecars (managed by astra) >>>" || $0=="# >>> pdf-sidecars pre-commit (managed by pdf-sidecars/setup.sh) >>>" {skip=1; next}
      $0=="# <<< pdf-sidecars <<<" || $0=="# <<< pdf-sidecars pre-commit <<<" {skip=0; next}
      !skip {print}' "$HOOK" > "$HOOK.tmp" && mv "$HOOK.tmp" "$HOOK" && chmod +x "$HOOK"
    grep -qvE '^[[:space:]]*(#!.*)?[[:space:]]*$' "$HOOK" || rm -f "$HOOK"
    echo "  removed the pdf-sidecars pre-commit block"
    ls "$HOOK".bak.* >/dev/null 2>&1 && echo "  kept the backup of your original hook: $(ls "$HOOK".bak.* | head -1 | sed 's#.*/##') (in $HOOKS; delete it when you no longer need it)"
  fi
  git -C "$TARGET" config --unset jsutils.path 2>/dev/null || true
  astra_remove pdf-sidecars
fi
uc_brew ocrmypdf  "OCR for scanned PDFs"
uc_brew tesseract "OCR engine"
uc_brew poppler   "provides pdftotext"
uc_brew weasyprint "HTML+CSS -> PDF renderer"
uc_keep pandoc "markdown converter shared by md2pdf and other tools"
uc_uv_tool marker-pdf "the Markdown sidecar generator"
