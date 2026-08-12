#!/usr/bin/env bash
# test-md2pdf.sh — md2pdf renders a real PDF via the real pandoc→weasyprint chain, and
# template selection fails loudly on a bad name (never a silent fallback to default).
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
MD2PDF="$HERE/../pdf-sidecars/md2pdf"
need pandoc "brew install pandoc"
need weasyprint "brew install weasyprint"

cat > "$SB/doc.md" <<'EOF'
# Astra test document
This paragraph contains the marker word XERAPHIM-4471 which must survive into the PDF text layer.
EOF

# happy path: real render, asserted by effect (magic bytes + extractable text)
assert_rc 0 "renders a PDF" "$MD2PDF" "$SB/doc.md" "$SB/doc.pdf"
assert_file "$SB/doc.pdf" "output PDF exists"
assert_eq "%PDF" "$(head -c 4 "$SB/doc.pdf")" "output starts with %PDF magic"
if python3 -c "import fitz" 2>/dev/null; then
  txt="$(python3 -c "import fitz,sys;print(' '.join(p.get_text() for p in fitz.open(sys.argv[1])))" "$SB/doc.pdf")"
  case "$txt" in *XERAPHIM-4471*) pass "marker text present in PDF text layer";; *) fail "marker text missing from PDF text layer";; esac
else
  # pymupdf absent: size floor is the weaker by-effect check — say so rather than silently thin out
  [ "$(stat -f%z "$SB/doc.pdf")" -gt 1000 ] && pass "PDF >1KB (pymupdf absent; text-layer check not run — weaker assert, stated)" || fail "PDF suspiciously small"
fi

# named template resolves from templates/ (the attorney-docs path used for real legal exports)
assert_rc 0 "named template 'attorney-docs' resolves and renders" "$MD2PDF" "$SB/doc.md" "$SB/doc2.pdf" --template attorney-docs
assert_file "$SB/doc2.pdf" "templated PDF exists"

# RED controls — the one-letter-off class: a near-miss template name must FAIL, not fall back
red "one-letter-off template name (attorney-doc) must fail" "$MD2PDF" "$SB/doc.md" "$SB/doc3.pdf" --template attorney-doc
assert_no_file "$SB/doc3.pdf" "no PDF produced from the failed template run"
red "missing input file must fail" "$MD2PDF" "$SB/no-such.md" "$SB/doc4.pdf"
red "no arguments must fail with usage" "$MD2PDF"

finish
