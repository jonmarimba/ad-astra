#!/usr/bin/env bash
# prose — install the prose ORCHESTRATOR skill: runs asd-ste100, humanizer and the
# pre-Grammarly pass in the one order that works and settles conflicts between them.
# Ships with grammarly-prep.md. The two skills it composes are separate tools
# (asd-ste100, humanizer) — the writing template installs all three together.
# Usage: ./install.sh --into <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../../agents-and-prompts/skills/prose"
TARGET=""
while [ $# -gt 0 ]; do case "$1" in --into) TARGET="${2:-}"; shift 2;; *) echo "prose: unknown argument: $1" >&2; exit 64;; esac; done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "prose: no such directory: $TARGET" >&2; exit 66; }
mkdir -p "$TARGET/.claude/skills/prose"
cp "$SRC/SKILL.md" "$SRC/grammarly-prep.md" "$TARGET/.claude/skills/prose/"
echo "prose: installed skill (+grammarly-prep) -> $TARGET/.claude/skills/prose/"
