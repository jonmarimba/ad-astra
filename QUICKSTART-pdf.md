# Quickstart: the legal-pdf template

PDFs are opaque to grep, to agents, and to anything else that reads text. The `legal-pdf` template installs a kit that writes text sidecars next to every PDF, plus a pre-commit hook that keeps them current. It composes `base`, so the full writing stack (QUICKSTART-writing.md) arrives with it. Written 2026-09-02 by Claude (Fable), reviewed against the live installer and kit.

## Install

```
cd js-db-ad-astra/tools/lib
python3 template.py install legal-pdf --into ~/path/to/YourRepo
```

The installer pulls the system dependencies (ocrmypdf, tesseract, and poppler via Homebrew; marker-pdf via uv), places the kit at `.astra/pdf-sidecars/`, and wires the hooks. Re-running the same command is the update path.

## The sidecars

For each `foo.pdf`, the kit writes:

- `foo.txt` — plain extracted text.
- `foo.ocr.txt` — OCR output, for scanned or image-only pages.
- `foo.layout.txt` — layout-preserving text that keeps table columns readable.
- `foo.marker.md` — Markdown, the richest structured form.
- `foo.metadata.md` — provenance for meeting-style PDFs, controlled by the policy knob below.

Sidecars are committed alongside their PDFs. That is the point: the repo's documents stay searchable as plain text, in git, forever.

## The hook

The pre-commit hook regenerates and stages sidecars for every staged PDF. If the kit is missing, the hook refuses the commit loudly, because a PDF with no text layer looks exactly like nothing being wrong. The installer manages only its own block in `.git/hooks/pre-commit`; anything else already in that hook is preserved, and the prior version is backed up.

## Backfill and bulk work

`.astra/pdf-sidecars/update_sidecars.sh` backfills sidecars for PDFs that were committed before the kit arrived. `reocr_all_pdfs_parallel.sh` re-runs OCR across the whole tree when the OCR engine improves.

## The metadata policy

`.metadata.md` generation is a git config knob, not a fork:

```
git config jsutils.metadataPolicy pattern    # pattern | all | none; default pattern
git config jsutils.metadataPattern 'minute|meeting|agenda|board|community'
```

The default `pattern` policy covers only files whose names look like meeting records. Set `all` for a repo where every PDF needs provenance.

## Producing documents, not only reading them

The kit also goes the other direction. `md2pdf input.md output.pdf --template legal.css` renders Markdown to PDF headlessly through pandoc and weasyprint, with CSS templates shipped beside it. `export_docx.py notes.md` produces a DOCX via pandoc. `pdf_add_footer.py` stamps a footer, Bates-style, onto an existing PDF.
