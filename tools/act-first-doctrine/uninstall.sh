#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — remove the act-first doctrine: the .doctrine/act-first.md file, its
# @-import blocks in CLAUDE.md/AGENTS.md, and its manifest entry.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
while [ $# -gt 0 ]; do case "$1" in --into) TARGET="${2:-}"; shift 2;; *) echo "act-first-doctrine: unknown argument: $1" >&2; exit 64;; esac; done
[ -n "$TARGET" ] || { echo "usage: uninstall.sh --into <repo>" >&2; exit 64; }
exec "$HERE/../lib/uninstall-doctrine.sh" "$TARGET" --slug act-first
