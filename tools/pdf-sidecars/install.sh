#!/usr/bin/env bash
# pdf-sidecars — install the PDF text-sidecar kit into a given repo.
#
# Two jobs, and the previous version only did the first:
#
#   1. System dependencies (ocrmypdf, tesseract, poppler, marker). Shared.
#   2. Wire a REPO: place the kit at <repo>/.astra/pdf-sidecars/ and install the
#      pre-commit hook that regenerates sidecars for staged PDFs.
#
# It used to ignore --into entirely and exit 0 after step 1, so the template
# layer recorded "legal-pdf installed" for a repo where nothing had been wired.
# A template that reports success while installing less than it claimed is the
# same shape as a test that passes against a broken implementation.
#
#   ./install.sh                  deps only
#   ./install.sh --into <repo>    deps + wire that repo
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

# The kit's own files, in the order a reader should meet them.
KIT_FILES="generate_pdf_sidecars.sh pdf_metadata.sh hook_pre_commit.sh update_sidecars.sh export_docx.py pdf_add_footer.py marked_to_pdf.sh reocr_all_pdfs.sh reocr_all_pdfs_parallel.sh"

install_deps() {
  command -v brew >/dev/null && brew bundle --file="$HERE/Brewfile" \
    || echo "no brew; ensure ocrmypdf, tesseract, poppler present"
  command -v uv >/dev/null || { echo "installing uv…"; curl -LsSf https://astral.sh/uv/install.sh | sh; }
  uv tool install marker-pdf || echo "marker-pdf install may need a retry"
}

# No --into: dependencies only, same as before.
case " $* " in
  *" --into "*) ;;
  *) install_deps; echo "pdf-sidecars deps ready. Wire a repo: $0 --into <repo>"; exit 0 ;;
esac

. "$HERE/../lib/astra-install.sh"
astra_target "$@"
install_deps
# shellcheck disable=SC2086
astra_place pdf-sidecars $KIT_FILES
chmod +x "$TARGET/.astra/pdf-sidecars/"*.sh

# ---------------------------------------------------------------------------
# The pre-commit hook.
#
# The hand-rolled hooks this replaces carried a silent pass: if the sidecar
# script was missing they printed a note and exited 0, so a PDF could be
# committed with no text sidecar and the commit would succeed. That is the
# failure that looks exactly like nothing being wrong, in repos whose whole
# purpose is that PDFs are searchable evidence. This block fails loudly instead.
# ---------------------------------------------------------------------------
HOOKS="$(git -C "$TARGET" rev-parse --git-path hooks)"
[ "${HOOKS#/}" != "$HOOKS" ] || HOOKS="$TARGET/$HOOKS"
mkdir -p "$HOOKS"
HOOK="$HOOKS/pre-commit"

BEGIN="# >>> pdf-sidecars (managed by astra) >>>"
END="# <<< pdf-sidecars <<<"

if [ -f "$HOOK" ]; then
  cp -p "$HOOK" "$HOOK.bak.$(date +%Y%m%d-%H%M%S)"
  echo "backed up existing pre-commit"
fi

# A repo that already had the old hand-rolled version gets it replaced wholesale;
# anything else is preserved and this block appended.
if [ -f "$HOOK" ] && ! grep -qF "$BEGIN" "$HOOK" \
   && ! grep -q "generate_pdf_sidecars" "$HOOK"; then
  KEEP="$(cat "$HOOK")"
else
  KEEP="#!/bin/bash"
fi

{
  printf '%s\n\n' "$KEEP"
  printf '%s\n' "$BEGIN"
  cat <<'BLOCK'
_kit="$(git rev-parse --show-toplevel)/.astra/pdf-sidecars/hook_pre_commit.sh"
if git -c core.quotePath=false diff --cached --name-only --diff-filter=ACM | grep -qi '\.pdf$'; then
    if [ ! -x "$_kit" ]; then
        echo "pre-commit: PDFs are staged but $_kit is missing." >&2
        echo "  Refusing to commit PDFs with no text sidecars. Reinstall:" >&2
        echo "    js-db-ad-astra/tools/pdf-sidecars/install.sh --into ." >&2
        exit 1
    fi
    "$_kit" || exit $?
fi
BLOCK
  printf '%s\n' "$END"
} > "$HOOK.astra-tmp"
mv -f "$HOOK.astra-tmp" "$HOOK"
chmod +x "$HOOK"
echo "wired pre-commit -> .astra/pdf-sidecars/hook_pre_commit.sh"

# The repo's own updater hook, so it pulls rather than astra pushing.
POST="$HOOKS/post-commit"
if [ ! -f "$POST" ]; then
  cp "$HERE/../lib/astra-post-commit.hook" "$POST"
  chmod +x "$POST"
  echo "installed post-commit updater"
fi
