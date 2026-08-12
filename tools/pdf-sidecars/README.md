# pdf-sidecars

AI-legible text sidecars for PDFs, generated automatically on commit. A PDF is
opaque to text tooling (grep, agents, graph ingestion); this kit writes, next to
each `foo.pdf`, the text layers an agent can actually read:

- `foo.txt` — plain text
- `foo.ocr.txt` — OCR'd text (`ocrmypdf --force-ocr`), for image-only/scanned pages
- `foo.layout.txt` — layout-preserving text (`pdftotext -layout`), keeps table columns
- `foo.marker.md` — Markdown (`marker`), the richest structured form
- `foo.metadata.md` — for meeting-style PDFs (policy-controlled, see below)

Designed to be a **flat git submodule** of any repo. One source of truth; update
the submodule and every repo's hook behavior updates with it (the hook resolves
the kit through `git config jsutils.path`, so there's nothing to re-splice).

## Requirements

`marker` (`uv tool install marker-pdf`), `ocrmypdf`, and `pdftotext` (poppler).

## Use it in a repo

```sh
git submodule add git@github.com:jonmarimba/pdf-sidecars.git tools/pdf-sidecars
tools/pdf-sidecars/setup.sh          # records jsutils.path + installs the pre-commit hook
tools/pdf-sidecars/update_sidecars.sh   # backfill sidecars for PDFs already committed
```

`setup.sh` is idempotent and **non-clobbering** — it only manages its own block
in `.git/hooks/pre-commit`; any other hook content is preserved.

## Contents

| script | role |
|---|---|
| `generate_pdf_sidecars.sh` | core: per-PDF sidecar generation (skip-if-exists; `FORCE=1` regenerates) |
| `hook_pre_commit.sh` | the pre-commit work — regenerate + stage sidecars for staged PDFs |
| `setup.sh` | installer: `jsutils.path` + non-clobbering hook splice |
| `update_sidecars.sh` | one-command backfill across a repo tree |
| `pdf_metadata.sh` | `.metadata.md` extraction for meeting-style PDFs |
| `reocr_all_pdfs.sh` / `…_parallel.sh` | bulk re-OCR utilities |
| `marked_to_pdf.sh` | render a `.marker.md` back to PDF |
| `pdf_add_footer.py` | stamp a footer (e.g. Bates-style) onto a PDF |
| `export_docx.py` | convert Markdown work-product → DOCX via pandoc (`export_docx.py notes.md` → `notes.docx`) |

## Metadata policy

`.metadata.md` generation is a config knob, not a fork:

```sh
git config jsutils.metadataPolicy  pattern|all|none    # default: pattern
git config jsutils.metadataPattern '<grep -E pattern>' # default: minute|meeting|agenda|board|community
```

(`SIDECAR_METADATA_POLICY` / `SIDECAR_METADATA_PATTERN` env vars override git config for one-off runs.)

## One local-only file

Exclude `cost.json` if any tool writes it; sidecars themselves are meant to be committed.
