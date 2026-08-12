#!/bin/bash
# hook_pre_commit.sh — the actual pre-commit work for PDF sidecars.
# The spliced hook block is a thin call into this script (resolved via
# `git config jsutils.path`), so updating js-utils updates hook behavior
# without re-splicing every repo.
#
# Behavior (same contract as the hand-rolled speedway/hoa/grandparent hooks):
# regenerate any missing/zero-byte sidecars for STAGED PDFs, then stage the
# sidecars alongside. Skip-if-exists semantics — a committed PDF whose
# sidecars already exist is untouched. SKIP_MARKER=1 etc. pass through from
# the environment.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

staged_pdfs=$(git -c core.quotePath=false diff --cached --name-only --diff-filter=ACM | grep -i '\.pdf$' || true)
[ -z "$staged_pdfs" ] && exit 0

repo_root=$(git rev-parse --show-toplevel)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/generate_pdf_sidecars.sh"   # sources process_pdf / list_sidecars, runs nothing

echo "js-utils pre-commit: processing staged PDFs..."
while IFS= read -r pdf; do
    [ -z "$pdf" ] && continue
    process_pdf "$repo_root/$pdf"
    while IFS= read -r sc; do
        [ -s "$sc" ] && git add "$sc"
    done < <(list_sidecars "$repo_root/$pdf")
done <<< "$staged_pdfs"

echo "PDFs scanned: $count_pdfs; sidecars generated: $count_gen"
if [ "$count_page_warnings" -gt 0 ]; then
    echo "⚠ $count_page_warnings zero-word-page warning(s) — see stderr." >&2
fi
exit 0
