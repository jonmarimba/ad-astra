#!/usr/bin/env bash
# uninstall.sh — dis-integrate pdf-sidecars. Its per-repo git hooks are removed IN each repo via
# hook-subtract.sh (not global), so this reports that and optionally removes the shared deps.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "pdf-sidecars dis-integrate:"
echo "  per-repo git hooks are NOT global — remove them inside each wired repo with:  $HERE/hook-subtract.sh"
uc_brew ocrmypdf  "OCR for scanned PDFs"
uc_brew tesseract "OCR engine"
uc_brew poppler   "provides pdftotext"
uc_brew weasyprint "HTML+CSS -> PDF renderer"
uc_keep pandoc "markdown converter shared by md2pdf and other tools"
uc_uv_tool marker-pdf "the Markdown sidecar generator"
echo "done."
