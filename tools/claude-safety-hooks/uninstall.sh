#!/bin/bash
# uninstall.sh — remove claude-safety-hooks from a target repo.
#
# Usage: ./uninstall.sh --into /path/to/target-repo [--keep-watchlist]
#        ./uninstall.sh --global                    [--keep-watchlist]
#
# Removes the two hook scripts and their PreToolUse/Bash entries from the settings file
# (--into: <target>/.claude/settings.local.json; --global: ~/.claude/settings.json). Only
# those two entries are removed -- any other hooks in that matcher are left alone, and the
# jq matches by script-name suffix so it clears both the $CLAUDE_PROJECT_DIR-relative and the
# absolute (global) command forms. The watchlist is DELETED by default, since it may carry
# tuning that shouldn't silently survive an uninstall and confuse a later reinstall; pass
# --keep-watchlist to leave it.
set -euo pipefail

TARGET=""
GLOBAL=0
KEEP_WATCHLIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="$2"; shift 2 ;;
    --global) GLOBAL=1; shift ;;
    --keep-watchlist) KEEP_WATCHLIST=1; shift ;;
    *) echo "uninstall.sh: unknown argument $1" >&2; exit 1 ;;
  esac
done

if [ "$GLOBAL" -eq 1 ] && [ -n "$TARGET" ]; then
  echo "uninstall.sh: --into and --global are mutually exclusive" >&2; exit 1
fi
if [ "$GLOBAL" -eq 0 ] && [ -z "$TARGET" ]; then
  echo "usage: uninstall.sh --into /path/to/target-repo | --global  [--keep-watchlist]" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "uninstall.sh: jq is required (brew install jq)" >&2
  exit 1
fi

if [ "$GLOBAL" -eq 1 ]; then
  HOOKS_DIR="$HOME/.claude/hooks"
  SETTINGS="$HOME/.claude/settings.json"
else
  HOOKS_DIR="$TARGET/.claude/hooks"
  SETTINGS="$TARGET/.claude/settings.local.json"
fi

rm -f "$HOOKS_DIR/no-silent-truncation.sh" "$HOOKS_DIR/no-killing-other-claudes.sh" \
      "$HOOKS_DIR/shell_word_literal.py" \
      "$HOOKS_DIR/no-killing-other-claudes.reap-hint"
if [ "$KEEP_WATCHLIST" -eq 0 ]; then
  rm -f "$HOOKS_DIR/no-silent-truncation.watchlist"
fi

if [ -f "$SETTINGS" ]; then
  TMP="$(mktemp)"
  jq '
    if .hooks and .hooks.PreToolUse then
      .hooks.PreToolUse |= map(
        if .matcher == "Bash" then
          .hooks |= map(select(
            (.command | test("no-silent-truncation.sh$") or test("no-killing-other-claudes.sh$")) | not
          ))
        else . end
      )
    else . end
  ' "$SETTINGS" > "$TMP"
  mv "$TMP" "$SETTINGS"
  echo "uninstall.sh: removed hook entries from $SETTINGS"
fi

echo "uninstall.sh: done."
