#!/usr/bin/env bash
# ios-ui-driving — install the ios-ui-driving SKILL into a repo's .claude/skills/.
#
# The skill is the "this is how we do it in Maharam" doctrine for driving iOS UI:
# accessibility identifiers mandatory, AX-tree targeting (never screenshots-as-perception),
# axe/ios-simulator probes for ad-hoc work, XCUITest-by-identifier promoted for flows a
# feature will exercise across many builds. Source of truth lives in
# agents-and-prompts/skills/ios-ui-driving/SKILL.md; this copies it per-repo (the cardinal
# rule: per-repo installs only, re-run to update). The axe CLI itself is the separate
# `axe` tool — the same templates install both.
#
# Dependencies: none beyond the checkout.
#
# Usage: ./install.sh --into <repo>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../../agents-and-prompts/skills/ios-ui-driving/SKILL.md"

TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="${2:-}"; shift 2 ;;
    *) echo "ios-ui-driving: unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "ios-ui-driving: no such directory: $TARGET" >&2; exit 66; }
[ -f "$SRC" ] || { echo "ios-ui-driving: FAIL — skill source missing at $SRC" >&2; exit 66; }

mkdir -p "$TARGET/.claude/skills/ios-ui-driving"
cp "$SRC" "$TARGET/.claude/skills/ios-ui-driving/SKILL.md"
echo "ios-ui-driving: installed skill -> $TARGET/.claude/skills/ios-ui-driving/SKILL.md"
exit 0
