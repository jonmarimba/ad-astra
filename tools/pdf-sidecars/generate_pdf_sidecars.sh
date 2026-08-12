#!/bin/bash
# Generate .txt, .ocr.txt, .layout.txt, .marker.md, and (for meeting PDFs)
# .metadata.md sidecars for PDFs. Single source of truth for sidecar
# generation logic.
# Called from both the post-scrape step in run_scrapers.sh and the pre-commit hook.
#
# Default mode: skip-if-exists. Only generates sidecars that are missing or
# zero-byte. Never overwrites an existing non-empty sidecar.
#
# Force mode: set FORCE=1 in the environment to regenerate everything.
#
# 2026-05-31: OCR pipeline switched from `--skip-text` to `--force-ocr` to
# fix a silent partial-extraction bug. With --skip-text, a PDF containing a
# mix of image-only and born-digital pages could produce a non-empty
# .ocr.txt missing entire pages, with no warning. --force-ocr re-OCRs every
# page; the per-page zero-word check below catches anything that still
# fails. .layout.txt now falls back to running pdftotext -layout on the
# OCR'd PDF when the source is image-only — financial-table scans
# preserve column structure instead of silently producing an empty layout
# sidecar. ocrmypdf stderr is no longer suppressed; failures surface in
# commit/script output instead of being hidden. Set SKIP_PDF_PAGE_CHECK=1
# to suppress page-level warnings (legitimately blank pages, cover sheets,
# watermark-only pages).
#
# Usage:
#   generate_pdf_sidecars.sh <pdf|directory> [<pdf|directory> ...]
#   FORCE=1 generate_pdf_sidecars.sh <directory>

set -u

FORCE="${FORCE:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA_SCRIPT="$SCRIPT_DIR/pdf_metadata.sh"

# Metadata-sidecar policy (js-utils canonicalization, 2026-08-07).
# The per-repo forks this replaces: speedway/hoa generated .metadata.md only
# for meeting-named PDFs; grandparentLegal forked the whole script to generate
# it for EVERY pdf (legal-document provenance). That policy difference is a
# config knob now, not a code fork:
#   git config jsutils.metadataPolicy  pattern|all|none    (default: pattern)
#   git config jsutils.metadataPattern '<grep -E pattern>' (default below)
# Env (SIDECAR_METADATA_POLICY / SIDECAR_METADATA_PATTERN) wins over git
# config, so one-off runs need no config churn.
METADATA_POLICY="${SIDECAR_METADATA_POLICY:-$(git config --get jsutils.metadataPolicy 2>/dev/null)}"
METADATA_POLICY="${METADATA_POLICY:-pattern}"
METADATA_PATTERN="${SIDECAR_METADATA_PATTERN:-$(git config --get jsutils.metadataPattern 2>/dev/null)}"
METADATA_PATTERN="${METADATA_PATTERN:-minute|meeting|agenda|board|community}"

metadata_wanted() {
    case "$METADATA_POLICY" in
        all)  return 0 ;;
        none) return 1 ;;
        *)    basename "$1" | tr '[:upper:]' '[:lower:]' | grep -qE "$METADATA_PATTERN" ;;
    esac
}

count_pdfs=0
count_gen=0
count_page_warnings=0

# Born-digital probe. Sample first / middle / last page of the source
# PDF via `pdftotext -f N -l N`. If each sample has at least
# BORN_DIGITAL_MIN_WORDS words (default 30), the PDF is treated as
# born-digital and ocrmypdf is skipped — pdftotext output is used
# directly for .ocr.txt. Returns 0 (true) / 1 (false).
#
# Why this exists: born-digital PDFs (Gmail thread exports, generated
# reports, scraped portal PDFs with native text) waste hours of CPU
# when --force-ocr re-rasterizes pages whose text is already perfect.
# The accretive case (multiple Gmail snapshots of the same growing
# thread) is the pathological one but the savings show up across the
# repo.
#
# Override: FORCE_OCR_BORN_DIGITAL=1 disables the skip (useful when a
# PDF has a known-corrupt text layer and OCR'd glyphs are preferred).
is_born_digital() {
    local pdf="$1"
    [ -n "${FORCE_OCR_BORN_DIGITAL:-}" ] && return 1
    local page_count
    page_count=$(pdfinfo "$pdf" 2>/dev/null | awk -F': *' '/^Pages:/ {print $2}')
    [ -z "$page_count" ] && return 1
    [ "$page_count" -le 0 ] && return 1
    local min_words="${BORN_DIGITAL_MIN_WORDS:-30}"
    local samples
    if [ "$page_count" -le 3 ]; then
        samples="$(seq 1 "$page_count")"
    else
        samples="1 $((page_count / 2)) $page_count"
    fi
    local p
    for p in $samples; do
        local words
        words=$(pdftotext -f "$p" -l "$p" "$pdf" - 2>/dev/null | wc -w | tr -d ' ')
        [ "$words" -lt "$min_words" ] && return 1
    done
    return 0
}

# Per-page zero-word check on an OCR'd PDF. Prints one warning per
# zero-word page to stderr and bumps count_page_warnings. Skipped when
# SKIP_PDF_PAGE_CHECK is set in the environment.
check_per_page() {
    local labeled_path="$1"
    local pdf_to_check="$2"
    [ -n "${SKIP_PDF_PAGE_CHECK:-}" ] && return 0
    local page_count
    page_count=$(pdfinfo "$pdf_to_check" 2>/dev/null | awk -F': *' '/^Pages:/ {print $2}')
    [ -z "$page_count" ] && return 0
    [ "$page_count" -le 0 ] && return 0
    local p=1
    while [ "$p" -le "$page_count" ]; do
        local words
        words=$(pdftotext -f "$p" -l "$p" "$pdf_to_check" - 2>/dev/null | wc -w | tr -d ' ')
        if [ "$words" -eq 0 ]; then
            echo "  ⚠ ZERO-WORD PAGE: $labeled_path page $p (of $page_count)" >&2
            count_page_warnings=$((count_page_warnings + 1))
        fi
        p=$((p + 1))
    done
}

process_pdf() {
    local pdf="$1"
    [ -f "$pdf" ] || return 0

    count_pdfs=$((count_pdfs + 1))

    local txt="${pdf%.[Pp][Dd][Ff]}.txt"
    local ocrtxt="${pdf%.[Pp][Dd][Ff]}.ocr.txt"
    local layouttxt="${pdf%.[Pp][Dd][Ff]}.layout.txt"
    local txt_ok=false
    local tmpocr=""

    # 1. Raw pdftotext extraction (operates on the source PDF; produces
    #    born-digital text when present, empty when the page is image-only).
    if [ "$FORCE" = "1" ] || [ ! -s "$txt" ]; then
        rm -f "$txt"
        if pdftotext "$pdf" "$txt" 2>/dev/null \
            && [ -s "$txt" ] \
            && [ "$(wc -w < "$txt" | tr -d ' ')" -gt 0 ]; then
            txt_ok=true
            count_gen=$((count_gen + 1))
        else
            rm -f "$txt"
        fi
    else
        txt_ok=true
    fi

    # 2. OCR'd extraction. --force-ocr re-runs OCR on every page so mixed
    #    image/text PDFs (e.g. a scanned cover sheet plus born-digital
    #    exhibits) don't silently lose pages the way --skip-text did.
    #    Stderr is captured (not suppressed) so we can categorize specific
    #    ocrmypdf errors and fall back gracefully instead of blocking.
    #
    #    Fallback rules:
    #    - DigitalSignatureError: signed PDFs (DocuSign etc.) can't be
    #      OCR'd without invalidating the signature. Use pdftotext output
    #      as .ocr.txt — signed PDFs ship with born-digital text.
    #    - EncryptedPdfError: password-protected PDFs. pdftotext usually
    #      also fails; log it and move on.
    #    - Other ocrmypdf errors: fall back to pdftotext output if
    #      available. Only block when BOTH methods produce nothing.
    if [ "$FORCE" = "1" ] || [ ! -s "$ocrtxt" ]; then
        rm -f "$ocrtxt"

        # 2a. Born-digital fast path. If every sampled page has real
        # text, skip ocrmypdf entirely — pdftotext already produced
        # the same content cleanly. Cuts hours off batches with lots
        # of Gmail thread exports, generated reports, or scraped
        # portal PDFs.
        if [ "$txt_ok" = true ] && is_born_digital "$pdf"; then
            echo "  ℹ BORN-DIGITAL-SKIP: source PDF has native text on every sampled page; OCR skipped: $pdf"
            cp "$txt" "$ocrtxt"
            count_gen=$((count_gen + 1))
        else
        tmpocr="/tmp/ocr_$(uuidgen).pdf"
        local ocr_stderr
        local ocr_status
        ocr_stderr=$(ocrmypdf --force-ocr --jobs "${OCRMYPDF_JOBS:-1}" --quiet "$pdf" "$tmpocr" 2>&1)
        ocr_status=$?
        if [ "$ocr_status" -eq 0 ]; then
            if pdftotext "$tmpocr" "$ocrtxt" 2>/dev/null \
                && [ -s "$ocrtxt" ] \
                && [ "$(wc -w < "$ocrtxt" | tr -d ' ')" -gt 0 ]; then
                count_gen=$((count_gen + 1))
                check_per_page "$pdf" "$tmpocr"
                # If raw pdftotext produced nothing, the source PDF is
                # image-only; use the OCR result as .txt too.
                if [ "$txt_ok" = false ] && [ ! -s "$txt" ]; then
                    cp "$ocrtxt" "$txt"
                fi
            else
                echo "  ⚠ post-OCR pdftotext failed or empty for $pdf" >&2
                rm -f "$ocrtxt"
                rm -f "$tmpocr"
                tmpocr=""
            fi
        else
            # ocrmypdf failed. Categorize and fall back to pdftotext if
            # available.
            rm -f "$tmpocr"
            tmpocr=""
            if echo "$ocr_stderr" | grep -q "DigitalSignatureError"; then
                if [ "$txt_ok" = true ]; then
                    echo "  ℹ DIGSIG-FALLBACK: digitally signed PDF; OCR skipped (would invalidate signature). Using pdftotext for .ocr.txt: $pdf"
                    cp "$txt" "$ocrtxt"
                    count_gen=$((count_gen + 1))
                else
                    echo "  ⚠ HARD-FAIL (DIGSIG): digitally signed PDF with no extractable born-digital text and OCR refused: $pdf" >&2
                fi
            elif echo "$ocr_stderr" | grep -q "EncryptedPdfError"; then
                if [ "$txt_ok" = true ]; then
                    echo "  ℹ ENCRYPTED-FALLBACK: encrypted PDF; OCR skipped. Using pdftotext for .ocr.txt: $pdf"
                    cp "$txt" "$ocrtxt"
                    count_gen=$((count_gen + 1))
                else
                    echo "  ⚠ HARD-FAIL (ENCRYPTED): $pdf — manual decryption required; no sidecars produced" >&2
                fi
            else
                if [ "$txt_ok" = true ]; then
                    echo "  ⚠ OTHER-FALLBACK: ocrmypdf --force-ocr failed for $pdf (falling back to pdftotext)" >&2
                    echo "$ocr_stderr" | head -2 >&2
                    cp "$txt" "$ocrtxt"
                    count_gen=$((count_gen + 1))
                else
                    echo "  ⚠ HARD-FAIL: both pdftotext and ocrmypdf failed for $pdf" >&2
                    echo "$ocr_stderr" | head -2 >&2
                fi
            fi
        fi
        fi
    fi

    # 3. Layout-preserving extraction. Try the source PDF first (this
    #    matters for born-digital financial reports, where column structure
    #    is intact). If the source has no born-digital text, fall back to
    #    running pdftotext -layout on the OCR'd PDF — ocrmypdf preserves
    #    original page geometry, so -layout still finds the column
    #    boundaries Tesseract laid down. Without this fallback,
    #    image-only financial scans produced an empty .layout.txt, and
    #    GL / AP / vendor-account analysis on scanned reports silently
    #    failed.
    if [ "$FORCE" = "1" ] || [ ! -s "$layouttxt" ]; then
        rm -f "$layouttxt"
        if pdftotext -layout "$pdf" "$layouttxt" 2>/dev/null \
            && [ -s "$layouttxt" ] \
            && [ "$(wc -w < "$layouttxt" | tr -d ' ')" -gt 0 ]; then
            count_gen=$((count_gen + 1))
        else
            rm -f "$layouttxt"
            local cleanup_tmpocr=false
            if [ -z "$tmpocr" ] || [ ! -s "$tmpocr" ]; then
                tmpocr="/tmp/ocr_$(uuidgen).pdf"
                cleanup_tmpocr=true
                if ! ocrmypdf --force-ocr --jobs "${OCRMYPDF_JOBS:-1}" --quiet "$pdf" "$tmpocr"; then
                    echo "  ⚠ ocrmypdf failed during layout fallback for $pdf" >&2
                    rm -f "$tmpocr"
                    tmpocr=""
                fi
            fi
            if [ -n "$tmpocr" ] && [ -s "$tmpocr" ]; then
                if pdftotext -layout "$tmpocr" "$layouttxt" 2>/dev/null \
                    && [ -s "$layouttxt" ] \
                    && [ "$(wc -w < "$layouttxt" | tr -d ' ')" -gt 0 ]; then
                    count_gen=$((count_gen + 1))
                else
                    rm -f "$layouttxt"
                fi
                if [ "$cleanup_tmpocr" = true ]; then
                    rm -f "$tmpocr"
                    tmpocr=""
                fi
            fi
        fi
    fi

    # Clean up any lingering tmpocr from step 2.
    [ -n "$tmpocr" ] && rm -f "$tmpocr"
    tmpocr=""

    # 4. Marker structured-markdown sidecar (.marker.md). marker_single
    #    (datalab-to/marker, installed via `uv tool install marker-pdf`)
    #    runs local layout/OCR models on the GPU and emits Markdown with
    #    real tables — scanned balance sheets cross-foot, photographed
    #    receipts yield itemized line items, redacted blocks appear as
    #    visible empty cells. Strictly better than .txt/.ocr.txt for
    #    structure; those remain for grep-compat and citation history.
    #    No LLM assist: tested against qwen3-vl — zero byte difference
    #    on born-digital, scanned, and photographed docs, at up to 2x
    #    the wall-clock. Skipped when marker_single is not on PATH or
    #    SKIP_MARKER=1 (e.g. a quick commit without the GPU dance;
    #    the next FORCE-less batch run backfills what was skipped).
    local markermd="${pdf%.[Pp][Dd][Ff]}.marker.md"
    if [ -z "${SKIP_MARKER:-}" ] && command -v marker_single >/dev/null 2>&1; then
        if [ "$FORCE" = "1" ] || [ ! -s "$markermd" ]; then
            rm -f "$markermd"
            local marker_out
            marker_out="/tmp/marker_$(uuidgen)"
            if marker_single "$pdf" --output_dir "$marker_out" \
                --disable_image_extraction --disable_multiprocessing \
                >/dev/null 2>&1; then
                # marker writes <out>/<pdf-stem>/<pdf-stem>.md
                local produced
                produced=$(find "$marker_out" -name '*.md' -type f | head -1)
                if [ -n "$produced" ] && [ -s "$produced" ]; then
                    cp "$produced" "$markermd"
                    count_gen=$((count_gen + 1))
                else
                    echo "  ⚠ marker_single produced no markdown for $pdf" >&2
                fi
            else
                echo "  ⚠ marker_single failed for $pdf" >&2
            fi
            rm -rf "$marker_out"
        fi
    fi

    # 5. Metadata sidecar, per policy (see metadata_wanted above)
    if metadata_wanted "$pdf"; then
        local metafile="${pdf%.[Pp][Dd][Ff]}.metadata.md"
        if [ "$FORCE" = "1" ] || [ ! -s "$metafile" ]; then
            rm -f "$metafile"
            if [ -x "$METADATA_SCRIPT" ]; then
                "$METADATA_SCRIPT" "$pdf" > "$metafile" 2>/dev/null
                if [ -s "$metafile" ]; then
                    count_gen=$((count_gen + 1))
                else
                    rm -f "$metafile"
                fi
            fi
        fi
    fi
}

# List sidecar paths for a given PDF (one per line). Used by callers that need
# to git-add freshly generated sidecars (e.g., the pre-commit hook).
list_sidecars() {
    local pdf="$1"
    echo "${pdf%.[Pp][Dd][Ff]}.txt"
    echo "${pdf%.[Pp][Dd][Ff]}.ocr.txt"
    echo "${pdf%.[Pp][Dd][Ff]}.layout.txt"
    echo "${pdf%.[Pp][Dd][Ff]}.marker.md"
    if metadata_wanted "$pdf"; then
        echo "${pdf%.[Pp][Dd][Ff]}.metadata.md"
    fi
}

# When sourced, expose process_pdf and list_sidecars; don't run anything.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 0 2>/dev/null || true
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <pdf|directory> [<pdf|directory> ...]" >&2
    exit 1
fi

for arg in "$@"; do
    if [ -d "$arg" ]; then
        while IFS= read -r -d '' pdf; do
            process_pdf "$pdf"
        done < <(find "$arg" -type f -iname '*.pdf' -print0)
    elif [ -f "$arg" ]; then
        process_pdf "$arg"
    else
        echo "Skipping (not a file or directory): $arg" >&2
    fi
done

echo "PDFs scanned: $count_pdfs; sidecars generated: $count_gen"
if [ "$count_page_warnings" -gt 0 ]; then
    echo "⚠ $count_page_warnings zero-word-page warning(s) — see stderr." >&2
fi
