#!/bin/bash
# update_sidecars.sh — "the script I can run to update": bring a repo's PDF
# sidecars current with one command.
#
#   update_sidecars.sh [dir]        backfill: generate any missing/zero-byte
#                                   sidecars across the tree (skip-if-exists;
#                                   this is the everyday "update")
#   FORCE=1 update_sidecars.sh [dir]  full regeneration (e.g. after a marker
#                                   version bump changes output quality)
#
# Defaults to the current git repo root (or cwd outside a repo). Prints the
# converter-tool versions first so every run records which vintage produced
# it — the "which marker made this .md" question should never need forensics
# again (it did, 2026-08-07: July markers were v1.x, unlabeled).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

echo "js-utils sidecar update — tool versions:"
echo "  pdftotext: $(pdftotext -v 2>&1 | head -1 || echo MISSING)"
echo "  ocrmypdf:  $(ocrmypdf --version 2>/dev/null || echo MISSING)"
echo "  marker:    $(uv tool list 2>/dev/null | grep '^marker-pdf' || echo 'MISSING (uv tool install marker-pdf)')"
echo "  target:    $TARGET  (FORCE=${FORCE:-0})"
echo

exec bash "$SCRIPT_DIR/generate_pdf_sidecars.sh" "$TARGET"
