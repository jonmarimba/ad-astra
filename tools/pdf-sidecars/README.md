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

## md2pdf — headless Markdown → PDF (replaces the Marked mouse-grab)
`marked_to_pdf.sh` drives Marked 2's Print dialog via UI scripting — it grabs the machine. `md2pdf` does it headless (pandoc → HTML+CSS → weasyprint), no GUI, no Marked, no browser:
```sh
md2pdf input.md output.pdf                       # default template
md2pdf input.md output.pdf --template legal.css  # your CSS (file, or templates/legal.css)
```
Templates are **CSS** (same styling model as Marked). Drop your legal template's CSS in `templates/` or point `--template` at it. Because md2pdf never touches Marked's own template store, the "don't clobber / version-conflict" worry disappears. `@page` in the CSS controls page size + margins. Footer parity via `pdf_add_footer.py` when pymupdf is present.

## Marked 3 scripted export — attempted 8/12, blocked by a Marked bug
Marked 3 (3.1.21, Setapp) ships an AppleScript dictionary with `convert_to` / `fetch_profile_names` / export profiles — on paper the native headless export. In practice the sdef's command codes are malformed (4–6 chars where AppleEvents require 8: `conv`, `gpls`, `mkopst`), so terminology never loads: AppleScript throws -2753, JXA -1708, by bundle id or path, app running or not. Until Brett fixes the dictionary, **md2pdf (pandoc→weasyprint + the attorney templates) is the headless legal-export path**, and `marked_to_pdf.sh` (UI-scripting Marked 2's print dialog) remains a deprecated fallback. Worth reporting upstream — support@marked2app.com / @ttscoff.

## Where this copy came from, and the question that is not settled

This directory is a SNAPSHOT of `git@github.com:jonmarimba/pdf-sidecars.git`, vendored into astra on 2026-08-12. The upstream repository's last commit is 2026-08-10, so nothing has diverged yet, and as of 2026-08-18 all three copies on this machine are byte-identical: this one, the standalone checkout at `~/svnCheckouts/pdf-sidecars`, and the older set in `js-utils/pdf` whose own commit message calls itself "the canonical PDF sidecar toolkit".

Three things each believing they are the source is the same drift this repo's registry was built to end, one level up. Astra's own rule says never to snapshot an external dependency as a local file, because freezing it cuts off updates — and that is exactly what this directory is.

The question is which way the arrow points, and it is Jonathan's to answer because it concerns a published repository of his:

- If the GitHub project is still the home, astra should pull from it on install rather than carrying a frozen copy, and `js-utils/pdf` should be retired.
- If astra is now the home, the GitHub repository should say so and the standalone checkout becomes a consumer like any other.

Until that is decided, do not resolve it by editing files here and letting them drift from the published repo. Nothing is broken today; the copies agree. What is missing is a stated direction of truth.
