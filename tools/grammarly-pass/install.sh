#!/usr/bin/env bash
# grammarly-pass — install the grammarly-pass skill: drive a real browser (claude-in-chrome
# or safari-mcp-stp) through Grammarly's web editor and triage its suggestions by Jonathan's
# standing rules (mechanical correctness accepted, voice flattening rejected, quoted
# material untouchable, judgement calls reported not applied).
# Usage: ./install.sh --into <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../../agents-and-prompts/skills/grammarly-pass"
TARGET=""
while [ $# -gt 0 ]; do case "$1" in --into) TARGET="${2:-}"; shift 2;; *) echo "grammarly-pass: unknown argument: $1" >&2; exit 64;; esac; done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "grammarly-pass: no such directory: $TARGET" >&2; exit 66; }
mkdir -p "$TARGET/.claude/skills/grammarly-pass"
cp "$SRC/SKILL.md" "$TARGET/.claude/skills/grammarly-pass/SKILL.md"
echo "grammarly-pass: installed skill -> $TARGET/.claude/skills/grammarly-pass/"
