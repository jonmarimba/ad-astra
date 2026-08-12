#!/bin/bash
# Parallel companion to reocr_all_pdfs.sh.
#
# Forks N worker processes (default: half the machine's logical cores,
# capped at 8) and dispatches PDFs via xargs -P. Each worker invokes
# the canonical generate_pdf_sidecars.sh with FORCE=1 for one PDF.
# Per-PDF stdout / stderr are interleaved as workers finish; status
# counts are aggregated by post-processing the per-worker log.
#
# Env vars:
#   REOCR_JOBS=N           Number of parallel workers. Default: max(1, ncpu/2),
#                          capped at 8. Set explicitly to override.
#   REOCR_LOG=path         Write per-PDF progress + warnings here.
#   REOCR_LIMIT=N          Smoke-test: only process the first N PDFs.
#   SKIP_PDF_PAGE_CHECK=1  Suppress zero-word-page warnings.
#
# Output: one line per worker completion to stdout (so xargs serializes
# them). All warnings (ocrmypdf failures, zero-word pages, etc.) land in
# the log file via stderr. Final summary at end.

set -u

cd "$(git rev-parse --show-toplevel)" || exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDECAR_SCRIPT="$SCRIPT_DIR/generate_pdf_sidecars.sh"

if [ ! -x "$SIDECAR_SCRIPT" ]; then
    echo "ERROR: $SIDECAR_SCRIPT not found or not executable" >&2
    exit 2
fi

# Pick a sane default job count
default_jobs() {
    local ncpu
    ncpu=$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4)
    local jobs=$(( ncpu / 2 ))
    [ "$jobs" -lt 1 ] && jobs=1
    [ "$jobs" -gt 8 ] && jobs=8
    echo "$jobs"
}

JOBS="${REOCR_JOBS:-$(default_jobs)}"
LOG="${REOCR_LOG:-}"
LIMIT="${REOCR_LIMIT:-0}"

if [ -n "$LOG" ]; then
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
    : > "$LOG"
fi

# Build the PDF list (NUL-delimited so spaces/unicode are preserved)
pdflist_nul="/tmp/reocr_pdflist_$$.nul"
find . -type d \( -name .git -o -name exports -o -name Archive -o -name .venv -o -name node_modules \) -prune \
    -o -type f -name '*.pdf' -print0 2>/dev/null \
    | sort -z > "$pdflist_nul"

count=$(tr -cd '\0' < "$pdflist_nul" | wc -c | tr -d ' ')

if [ "$LIMIT" -gt 0 ]; then
    # Truncate to first N NUL-delimited records. macOS awk/head don't
    # handle NUL bytes in output reliably, so use Python instead — it's
    # always available and round-trips bytes correctly.
    python3 -c "
import sys
n = int(sys.argv[1])
data = open('$pdflist_nul', 'rb').read()
parts = data.split(b'\\x00')[:n]
sys.stdout.buffer.write(b'\\x00'.join(parts) + b'\\x00')
" "$LIMIT" > "${pdflist_nul}.lim"
    mv "${pdflist_nul}.lim" "$pdflist_nul"
    count=$(tr -cd '\0' < "$pdflist_nul" | wc -c | tr -d ' ')
    echo "REOCR_LIMIT=$LIMIT — capped to $count PDFs."
fi

echo "Found $count PDFs to process."
echo "Workers: $JOBS"
echo "Log:     ${LOG:-(stdout only)}"
echo ""

# Per-PDF worker. Snapshot-hash the sidecars before, process, snapshot
# after, emit a single status line to stdout. Stderr (warnings) flows
# to the parent's stderr and gets captured in the log via the outer
# redirect.
worker() {
    local pdf="$1"
    [ -f "$pdf" ] || { echo "SKIP|missing|$pdf"; return; }

    local sigfile="/tmp/reocr_sig_$$_$RANDOM"
    : > "$sigfile"
    for ext in .txt .ocr.txt .layout.txt .metadata.md; do
        local sc="${pdf%.pdf}${ext}"
        [ -s "$sc" ] && shasum -a 256 "$sc" >> "$sigfile" 2>/dev/null
    done

    FORCE=1 "$SIDECAR_SCRIPT" "$pdf" >/dev/null 2>>"${LOG:-/dev/stderr}"
    local rc=$?

    local changed=0
    for ext in .txt .ocr.txt .layout.txt .metadata.md; do
        local sc="${pdf%.pdf}${ext}"
        if [ -s "$sc" ]; then
            local now
            now=$(shasum -a 256 "$sc" 2>/dev/null)
            if ! grep -qF "$now" "$sigfile" 2>/dev/null; then
                changed=1
                echo "$sc" >> "/tmp/reocr_changed_$$.txt"
            fi
        fi
    done
    rm -f "$sigfile"

    if [ "$rc" -ne 0 ]; then
        echo "FAIL|rc=$rc|$pdf"
    elif [ "$changed" -eq 1 ]; then
        echo "CHANGED|$pdf"
    else
        echo "UNCHANGED|$pdf"
    fi
}
export -f worker
export SIDECAR_SCRIPT LOG SKIP_PDF_PAGE_CHECK

# Empty the changed-list file
: > "/tmp/reocr_changed_$$.txt"

# Run workers in parallel via xargs -P. Each line of output is one
# completed PDF's status.
results_tmp="/tmp/reocr_results_$$.txt"
xargs -0 -n 1 -P "$JOBS" -I{} bash -c 'worker "$@"' _ {} < "$pdflist_nul" > "$results_tmp"

# Aggregate
total=$(wc -l < "$results_tmp" | tr -d ' ')
changed=$(grep -c '^CHANGED|' "$results_tmp" 2>/dev/null || echo 0)
unchanged=$(grep -c '^UNCHANGED|' "$results_tmp" 2>/dev/null || echo 0)
failed=$(grep -c '^FAIL|' "$results_tmp" 2>/dev/null || echo 0)
skipped=$(grep -c '^SKIP|' "$results_tmp" 2>/dev/null || echo 0)
zero_pages=0
if [ -n "$LOG" ] && [ -f "$LOG" ]; then
    zero_pages=$(grep -c 'ZERO-WORD PAGE' "$LOG" 2>/dev/null || echo 0)
fi

echo "==== Parallel re-OCR summary ===="
echo "Processed:           $total"
echo "Sidecars changed:    $changed"
echo "Sidecars unchanged:  $unchanged"
echo "Failures:            $failed"
echo "Skipped (missing):   $skipped"
echo "Zero-word warnings:  $zero_pages (in log: ${LOG:-stderr})"
echo ""
echo "Changed-sidecar list: /tmp/reocr_changed_$$.txt"
echo "Per-PDF status list:  $results_tmp"

# Stash for easier post-processing
cp "/tmp/reocr_changed_$$.txt" "/tmp/reocr_changed_latest.txt"
cp "$results_tmp" "/tmp/reocr_results_latest.txt"

rm -f "$pdflist_nul"
