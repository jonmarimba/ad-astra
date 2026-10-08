#!/usr/bin/env bash
# deps.sh — the machine half of pdf-sidecars: ocrmypdf, tesseract, poppler and marker. install.sh
# with no --into does exactly this and wires no repo, so `astra upgrade` calls it.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/install.sh"
