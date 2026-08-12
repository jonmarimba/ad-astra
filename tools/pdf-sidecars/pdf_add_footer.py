#!/usr/bin/env python3
import sys
from pathlib import Path
import os

import fitz


FONT_NAME = "TimesNewRomanPSMT"
FONT_FILE = "/System/Library/Fonts/Supplemental/Times New Roman.ttf"
FONT_SIZE = 10
LEFT_X = 36
RIGHT_X = 576
BOTTOM_MARGIN = 24
TEXT_ASCENT = 12


def add_footer(pdf_path: Path, footer_text: str) -> None:
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    font = fitz.Font(fontfile=FONT_FILE)

    for page_number, page in enumerate(doc, start=1):
        page_height = page.rect.height
        baseline_y = page_height - TEXT_ASCENT
        footer_rect = fitz.Rect(
            LEFT_X,
            page_height - BOTTOM_MARGIN,
            RIGHT_X,
            page_height,
        )

        # White out any existing footer content in the target band first.
        page.draw_rect(footer_rect, color=None, fill=(1, 1, 1), overlay=True)

        page.insert_text(
            fitz.Point(LEFT_X, baseline_y),
            footer_text,
            fontname=FONT_NAME,
            fontfile=FONT_FILE,
            fontsize=FONT_SIZE,
            overlay=True,
        )
        page.insert_text(
            fitz.Point(RIGHT_X - font.text_length(str(page_number), fontsize=FONT_SIZE), baseline_y),
            str(page_number),
            fontname=FONT_NAME,
            fontfile=FONT_FILE,
            fontsize=FONT_SIZE,
            overlay=True,
        )

    temp_path = pdf_path.with_suffix(pdf_path.suffix + ".tmp")
    doc.save(temp_path, garbage=4, deflate=True)
    doc.close()
    os.replace(temp_path, pdf_path)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} file.pdf", file=sys.stderr)
        return 2

    pdf_path = Path(sys.argv[1])
    if not pdf_path.is_file():
        print(f"pdf file not found: {pdf_path}", file=sys.stderr)
        return 1

    add_footer(pdf_path, pdf_path.stem)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
