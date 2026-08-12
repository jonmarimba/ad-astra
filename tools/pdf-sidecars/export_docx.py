#!/usr/bin/env python3
"""Convert Markdown work-product to DOCX via pandoc, with clean print styling.

Generic — no hardcoded file lists. Each input .md becomes a sibling .docx,
or pass explicit input/output pairs with --pairs.

    export_docx.py notes.md                 # -> notes.docx (beside it)
    export_docx.py a.md b.md                # -> a.docx and b.docx
    export_docx.py --pairs in.md out/x.docx # explicit input/output pairs

Requires: pandoc  (brew install pandoc)

(Distilled from the per-matter export_docx.py in the legal repos; the
HOA-specific DEFAULT_EXPORTS list and the "Demands Matrix" table special-case
were dropped — pandoc handles Markdown tables natively.)
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def markdown_to_html(text: str) -> str:
    with tempfile.TemporaryDirectory() as tmpdir:
        temp_md = Path(tmpdir) / "input.md"
        temp_html = Path(tmpdir) / "output.html"
        temp_md.write_text(text)
        subprocess.run(
            ["pandoc", str(temp_md), "-t", "html5", "-o", str(temp_html)],
            check=True,
        )
        return temp_html.read_text()


def wrap_html_document(body_html: str) -> str:
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {{
      font-family: Georgia, "Times New Roman", serif;
      font-size: 11pt;
      line-height: 1.25;
      margin: 0.6in;
    }}
    table {{ width: 100%; border-collapse: collapse; margin: 0.5em 0 1em 0; }}
    th, td {{ border: 1px solid #999; padding: 6pt 8pt; vertical-align: top; text-align: left; }}
    p {{ margin: 0 0 0.5em 0; }}
    td p:last-child {{ margin-bottom: 0; }}
  </style>
</head>
<body>
{body_html}
</body>
</html>
"""


def export_docx(input_path: Path, output_path: Path) -> None:
    html_doc = wrap_html_document(markdown_to_html(input_path.read_text()))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmpdir:
        temp_html = Path(tmpdir) / f"{input_path.stem}.html"
        temp_html.write_text(html_doc)
        subprocess.run(
            ["pandoc", str(temp_html), "-o", str(output_path), "--metadata=title:"],
            check=True,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert Markdown to DOCX via pandoc.")
    parser.add_argument(
        "inputs",
        nargs="+",
        help="Markdown files (each -> sibling .docx), or input/output pairs with --pairs.",
    )
    parser.add_argument(
        "--pairs",
        action="store_true",
        help="Treat args as input.md output.docx pairs instead of standalone inputs.",
    )
    args = parser.parse_args()

    if not shutil.which("pandoc"):
        parser.error("pandoc not found. Install it:  brew install pandoc")

    if args.pairs:
        if len(args.inputs) % 2 != 0:
            parser.error("--pairs needs an even number of args (input.md output.docx ...).")
        pairs = [
            (Path(args.inputs[i]), Path(args.inputs[i + 1]))
            for i in range(0, len(args.inputs), 2)
        ]
    else:
        pairs = [(Path(p), Path(p).with_suffix(".docx")) for p in args.inputs]

    rc = 0
    for src, dst in pairs:
        if not src.is_file():
            print(f"skip (not a file): {src}", file=sys.stderr)
            rc = 1
            continue
        export_docx(src, dst)
        print(dst)
    return rc


if __name__ == "__main__":
    sys.exit(main())
