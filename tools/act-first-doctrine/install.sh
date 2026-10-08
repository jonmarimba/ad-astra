#!/usr/bin/env bash
# astra-scope: repo
# act-first-doctrine — install the act-first doctrine (do obvious, reversible, local work without asking; ask only at one-way doors)
# Usage: ./install.sh --into <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
while [ $# -gt 0 ]; do case "$1" in --into) TARGET="${2:-}"; shift 2;; *) echo "act-first-doctrine: unknown argument: $1" >&2; exit 64;; esac; done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
exec "$HERE/../lib/install-doctrine.sh" "$TARGET" "$HERE/../../agents-and-prompts/doctrine/act-first.md" --slug act-first
