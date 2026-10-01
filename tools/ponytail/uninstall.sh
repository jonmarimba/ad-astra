#!/usr/bin/env bash
# uninstall.sh — remove the ponytail skills from one repo. The inverse the installer's
# own header documents: rm -rf <repo>/.claude/skills/ponytail (and ponytail-audit).
set -euo pipefail
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) REPO="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$REPO" ] || { echo "usage: uninstall.sh --into <repo>" >&2; exit 64; }
[ -d "$REPO" ] || { echo "uninstall.sh: no such directory: $REPO" >&2; exit 66; }
rm -rf "$REPO/.claude/skills/ponytail" "$REPO/.claude/skills/ponytail-audit"
echo "removed ponytail skills from $REPO/.claude/skills"
