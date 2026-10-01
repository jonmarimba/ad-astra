#!/usr/bin/env bash
# asd-ste100 — install the ASD-STE100 Simplified Technical English skill (sentence
# mechanics: complete sentences, active voice, one idea per sentence) into a repo's
# .claude/skills/. Source of truth: agents-and-prompts/skills/asd-ste100/SKILL.md.
# Usage: ./install.sh --into <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../../agents-and-prompts/skills/asd-ste100"
TARGET=""
while [ $# -gt 0 ]; do case "$1" in --into) TARGET="${2:-}"; shift 2;; *) echo "asd-ste100: unknown argument: $1" >&2; exit 64;; esac; done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "asd-ste100: no such directory: $TARGET" >&2; exit 66; }
mkdir -p "$TARGET/.claude/skills/asd-ste100"
cp "$SRC/SKILL.md" "$TARGET/.claude/skills/asd-ste100/SKILL.md"
echo "asd-ste100: installed skill -> $TARGET/.claude/skills/asd-ste100/"
