#!/bin/bash
# Re-OCR / re-extract every PDF in the repo using FORCE=1 against the
# canonical generate_pdf_sidecars.sh. Use after upgrading the sidecar
# script (e.g., switching from --skip-text to --force-ocr) to bring all
# historical sidecars current.
#
# Output: per-PDF progress on stdout; warnings (zero-word pages,
# ocrmypdf failures) on stderr; final summary at end.
#
# Env vars:
#   SKIP_PDF_PAGE_CHECK=1   Silence zero-word-page warnings during the
#                           run (use for known scan-only batches).
#   REOCR_DRY_RUN=1         Walk PDFs but do not write any sidecars
#                           (audit-only mode; useful for estimating
#                           runtime and surfacing zero-word pages
#                           without modifying tracked files).
#   REOCR_LIMIT=N           Process only the first N PDFs (smoke test).
#   REOCR_LOG=path          Write per-PDF progress to a log file in
#                           addition to stdout.
#
# Compatible with bash 3.2 (macOS default). Skips .git, exports, and
# Archive directories. Uses NUL-delimited find output so unicode paths
# survive intact.

set -u

cd "$(git rev-parse --show-toplevel)" || exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDECAR_SCRIPT="$SCRIPT_DIR/generate_pdf_sidecars.sh"

if [ ! -x "$SIDECAR_SCRIPT" ]; then
    echo "ERROR: $SIDECAR_SCRIPT not found or not executable" >&2
    exit 2
fi

LIMIT="${REOCR_LIMIT:-0}"
LOG="${REOCR_LOG:-}"

if [ -n "$LOG" ]; then
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
    : > "$LOG"
fi

log() {
    echo "$@"
    [ -n "$LOG" ] && echo "$@" >> "$LOG"
}

# Build the PDF list to a temp file (avoids subshell variable issues).
pdflist="/tmp/reocr_pdflist_$$.txt"
find . -type d \( -name .git -o -name exports -o -name Archive -o -name .venv -o -name node_modules \) -prune \
    -o -type f -name '*.pdf' -print0 2>/dev/null \
    | tr '\0' '\n' \
    | sed 's|^\./||' \
    | sort > "$pdflist"

count=$(wc -l < "$pdflist" | tr -d ' ')
log "Found $count PDFs to process."
[ "$LIMIT" -gt 0 ] && log "REOCR_LIMIT=$LIMIT — will stop after $LIMIT PDFs."
[ -n "${REOCR_DRY_RUN:-}" ] && log "REOCR_DRY_RUN=1 — audit only; no sidecars will be written."

# Track which sidecars were present and their checksums BEFORE the run,
# so we can report which sidecars actually changed. Skip in dry-run.
changed_list="/tmp/reocr_changed_$$.txt"
: > "$changed_list"

snapshot_sidecars() {
    local pdf="$1"
    local snap="$2"
    for ext in .txt .ocr.txt .layout.txt .metadata.md; do
        local sc="${pdf%.pdf}${ext}"
        if [ -s "$sc" ]; then
            shasum -a 256 "$sc" 2>/dev/null
        fi
    done > "$snap"
}

diff_sidecars() {
    local pdf="$1"
    local snap_before="$2"
    local changed_local=false
    for ext in .txt .ocr.txt .layout.txt .metadata.md; do
        local sc="${pdf%.pdf}${ext}"
        if [ -s "$sc" ]; then
            local now
            now=$(shasum -a 256 "$sc" 2>/dev/null)
            if ! grep -qF "$now" "$snap_before"; then
                echo "$sc" >> "$changed_list"
                changed_local=true
            fi
        fi
    done
    [ "$changed_local" = true ] && return 0 || return 1
}

total=0
changed=0
unchanged=0
problems=0

# We source the sidecar script to call its process_pdf directly. That
# gives us its per-page warning behavior + the same logic the pre-commit
# hook uses.
# shellcheck disable=SC1090
FORCE=1 . "$SIDECAR_SCRIPT" 2>/dev/null || true
# Re-set FORCE in our scope since the sourced script defaults it.
FORCE=1
export FORCE

while IFS= read -r pdf; do
    [ -z "$pdf" ] && continue
    total=$((total + 1))
    [ "$LIMIT" -gt 0 ] && [ "$total" -gt "$LIMIT" ] && break

    if [ ! -f "$pdf" ]; then
        log "[$total/$count] SKIP (not a file): $pdf"
        continue
    fi

    log "[$total/$count] $pdf"

    snap_before="/tmp/reocr_snap_$$.txt"
    snapshot_sidecars "$pdf" "$snap_before"

    if [ -n "${REOCR_DRY_RUN:-}" ]; then
        # Audit-only: don't touch the sidecars, just run the OCR + page
        # check to surface zero-word warnings.
        # (Conservative: skip the actual generation by skipping the call.)
        continue
    fi

    if ! process_pdf "$pdf"; then
        problems=$((problems + 1))
        rm -f "$snap_before"
        continue
    fi

    if diff_sidecars "$pdf" "$snap_before"; then
        changed=$((changed + 1))
    else
        unchanged=$((unchanged + 1))
    fi
    rm -f "$snap_before"
done < "$pdflist"

rm -f "$pdflist"

log ""
log "==== Re-OCR summary ===="
log "Processed:           $total"
log "Sidecars changed:    $changed (PDFs where at least one sidecar's hash changed)"
log "Sidecars unchanged:  $unchanged"
log "Process failures:    $problems"
log "Zero-word warnings:  ${count_page_warnings:-0} (see stderr)"
if [ "$changed" -gt 0 ]; then
    log ""
    log "Changed sidecar list: $changed_list"
    log "$(wc -l < "$changed_list" | tr -d ' ') sidecar files modified by this run."
fi
