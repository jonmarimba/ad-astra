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
# md2pdf is the headless PDF path and it was MISSING from this list until
# 2026-08-25, so every repo wired by this installer got only marked_to_pdf.sh —
# which drives Marked 2 through the GUI and seizes the screen mid-export. The
# headless exporter existed in the toolbox the whole time and simply never
# shipped to a single repo. Its CSS templates ship with it; without them md2pdf
# exits on a missing default.css.
KIT_FILES="generate_pdf_sidecars.sh pdf_metadata.sh hook_pre_commit.sh update_sidecars.sh export_docx.py pdf_add_footer.py md2pdf marked_to_pdf.sh reocr_all_pdfs.sh reocr_all_pdfs_parallel.sh"

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
# md2pdf resolves a bare --template NAME against ./templates/NAME.css relative to
# its own directory, so the stylesheets have to travel with it.
mkdir -p "$TARGET/.astra/pdf-sidecars/templates"
cp -p "$HERE/templates/"*.css "$TARGET/.astra/pdf-sidecars/templates/" 2>/dev/null || true
chmod +x "$TARGET/.astra/pdf-sidecars/"*.sh "$TARGET/.astra/pdf-sidecars/md2pdf"

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

# PRESERVE THE REPO'S OWN HOOK CONTENT. Only this tool's managed block is ever
# replaced. An earlier version here discarded the whole file whenever it found
# the old hand-rolled sidecar code, which would have silently eaten any
# repo-specific guard living in the same hook — js-hoa has one that refuses
# commits deleting scraped evidence. A tool that removes somebody else's work
# while installing itself is the same disease as the sync that overwrote local
# edits, one layer up.
if [ -f "$HOOK" ]; then
  KEEP="$(python3 - "$HOOK" "$BEGIN" "$END" <<'PY'
import sys, pathlib
hook, begin, end = sys.argv[1], sys.argv[2], sys.argv[3]
lines = pathlib.Path(hook).read_text().splitlines()
out, skipping = [], False
for line in lines:
    if line.strip() == begin:
        skipping = True
        continue
    if line.strip() == end:
        skipping = False
        continue
    if not skipping:
        out.append(line)
# Drop the old hand-rolled sidecar hook, which the managed block replaces. It is
# recognised by its own call, not by position.
text = "\n".join(out)
if "generate_pdf_sidecars" in text and begin not in text:
    text = "#!/bin/bash"
print(text.rstrip() or "#!/bin/bash")
PY
)"
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
