#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
command -v brew >/dev/null && brew bundle --file="$HERE/Brewfile" || echo "no brew; ensure ocrmypdf, tesseract, poppler present"
# marker (the Markdown sidecar generator) is a uv tool
command -v uv >/dev/null || { echo "installing uv…"; curl -LsSf https://astral.sh/uv/install.sh | sh; }
uv tool install marker-pdf || echo "marker-pdf install may need a retry"
echo "pdf-sidecars deps ready. Wire a repo: $HERE/setup.sh   |  Unwire: $HERE/hook-subtract.sh"
