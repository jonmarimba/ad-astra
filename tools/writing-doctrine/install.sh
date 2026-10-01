#!/usr/bin/env bash
# writing-doctrine — install Jonathan's writing doctrine (above-the-sentence rules:
# what belongs in a document, recipient address, ask structure) as .doctrine/writing.md
# with @-imports in CLAUDE.md/AGENTS.md. Delegates to the shared doctrine installer.
# Usage: ./install.sh --into <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
while [ $# -gt 0 ]; do case "$1" in --into) TARGET="${2:-}"; shift 2;; *) echo "writing-doctrine: unknown argument: $1" >&2; exit 64;; esac; done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
exec "$HERE/../lib/install-doctrine.sh" "$TARGET" "$HERE/../../agents-and-prompts/doctrine/writing.md" --slug writing
