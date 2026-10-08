#!/usr/bin/env bash
# deps.sh — install or upgrade the AXe CLI (cameroncooke/axe).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
command -v brew >/dev/null || { echo "axe: FAIL: brew missing" >&2; exit 69; }
if command -v axe >/dev/null; then brew upgrade cameroncooke/axe/axe >/dev/null 2>&1 || true
else brew install cameroncooke/axe/axe; fi
axe --version >/dev/null 2>&1 || command -v axe >/dev/null || { echo "axe: FAIL: not on PATH after install" >&2; exit 69; }
