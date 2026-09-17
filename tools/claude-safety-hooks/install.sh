#!/bin/bash
# install.sh — install claude-safety-hooks either into a target repo (--into) or into the
# user's GLOBAL Claude config (--global), wiring them into PreToolUse/Bash (merged
# additively, never clobbering existing hooks).
#
# Usage:
#   ./install.sh --into /path/to/target-repo [--reap-hint "text naming your reap mechanism"]
#   ./install.sh --global                    [--reap-hint "..."]
#
# --into  writes <target>/.claude/hooks/ + <target>/.claude/settings.local.json, wired with
#         $CLAUDE_PROJECT_DIR-relative paths (the per-repo default; still the right call for
#         anything repo-specific).
# --global writes ~/.claude/hooks/ + ~/.claude/settings.json, wired with an ABSOLUTE path
#         (resolved at install time — global settings are machine-local, never cloned, so a
#         concrete path is correct and does not depend on which repo is open). Use this for
#         the SAFETY hooks specifically: they protect against silent data loss and killing a
#         live claude regardless of which repo you are in, so a per-repo install leaves every
#         un-installed repo unguarded. This is the deliberate carve-out to astra's
#         "nothing installed globally" default — it applies to these protective hooks, NOT to
#         tools or doctrine, which stay per-repo. (Jonathan, 2026-09-17: the install scripts
#         should allow global install "where potentially applicable" — this is that case.)
#
# What it does (either mode):
#   1. Copies no-silent-truncation.sh, no-killing-other-claudes.sh, shell_word_literal.py
#      into <hooks dir>, executable.
#   2. Seeds <hooks dir>/no-silent-truncation.watchlist from the .default file HERE, but only
#      if one isn't already there — never overwrites a tuned watchlist on a re-run.
#   3. --reap-hint (optional) is written as plain data to no-killing-other-claudes.reap-hint.
#   4. Merges PreToolUse/Bash hook entries into the settings file via jq, additively — an
#      existing Bash hook list is preserved, and re-running does not duplicate entries.
#
# Requires: jq (brew install jq).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
GLOBAL=0
REAP_HINT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="$2"; shift 2 ;;
    --global) GLOBAL=1; shift ;;
    --reap-hint) REAP_HINT="$2"; shift 2 ;;
    *) echo "install.sh: unknown argument $1" >&2; exit 1 ;;
  esac
done

# Exactly one of --into / --global.
if [ "$GLOBAL" -eq 1 ] && [ -n "$TARGET" ]; then
  echo "install.sh: --into and --global are mutually exclusive" >&2; exit 1
fi
if [ "$GLOBAL" -eq 0 ] && [ -z "$TARGET" ]; then
  echo "usage: install.sh --into /path/to/target-repo | --global  [--reap-hint TEXT]" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "install.sh: jq is required (brew install jq)" >&2
  exit 1
fi

if [ "$GLOBAL" -eq 1 ]; then
  HOOKS_DIR="$HOME/.claude/hooks"
  SETTINGS="$HOME/.claude/settings.json"
  # Absolute, resolved now — a global hook must not depend on $CLAUDE_PROJECT_DIR, which
  # changes with whichever repo is open. Machine-local file, so a concrete path is correct.
  CMD_PREFIX="$HOOKS_DIR"
else
  if [ ! -d "$TARGET" ]; then
    echo "install.sh: target repo not found: $TARGET" >&2; exit 1
  fi
  HOOKS_DIR="$TARGET/.claude/hooks"
  SETTINGS="$TARGET/.claude/settings.local.json"
  # $CLAUDE_PROJECT_DIR is expanded by Claude Code at hook-run time to the open repo.
  CMD_PREFIX="\$CLAUDE_PROJECT_DIR/.claude/hooks"
fi

mkdir -p "$HOOKS_DIR"

cp "$HERE/no-silent-truncation.sh" "$HOOKS_DIR/no-silent-truncation.sh"
cp "$HERE/no-killing-other-claudes.sh" "$HOOKS_DIR/no-killing-other-claudes.sh"
cp "$HERE/shell_word_literal.py" "$HOOKS_DIR/shell_word_literal.py"
chmod +x "$HOOKS_DIR/no-silent-truncation.sh" "$HOOKS_DIR/no-killing-other-claudes.sh"
chmod +x "$HOOKS_DIR/shell_word_literal.py"

if [ -n "$REAP_HINT" ]; then
  printf '%s' "$REAP_HINT" > "$HOOKS_DIR/no-killing-other-claudes.reap-hint"
fi

WATCHLIST="$HOOKS_DIR/no-silent-truncation.watchlist"
if [ -f "$WATCHLIST" ]; then
  echo "install.sh: leaving existing watchlist in place: $WATCHLIST"
else
  cp "$HERE/no-silent-truncation.watchlist.default" "$WATCHLIST"
  echo "install.sh: seeded a starter watchlist at $WATCHLIST -- edit it to name YOUR search tools"
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

TMP="$(mktemp)"
jq --arg trunc "$CMD_PREFIX/no-silent-truncation.sh" \
   --arg kill  "$CMD_PREFIX/no-killing-other-claudes.sh" '
  .hooks //= {} |
  .hooks.PreToolUse //= [] |
  (.hooks.PreToolUse | map(.matcher == "Bash") | index(true)) as $idx |
  if $idx == null then
    .hooks.PreToolUse += [{"matcher": "Bash", "hooks": []}]
  else . end
  | (.hooks.PreToolUse | map(.matcher == "Bash") | index(true)) as $idx2
  | .hooks.PreToolUse[$idx2].hooks as $existing
  | .hooks.PreToolUse[$idx2].hooks =
      ($existing
        + ([$trunc, $kill]
           | map({"type": "command", "command": .})
           | map(select(. as $new | ($existing | map(.command) | index($new.command)) == null)))
      )
' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

echo "install.sh: wired into $SETTINGS (PreToolUse/Bash, merged additively)"
if [ "$GLOBAL" -eq 1 ]; then
  echo "install.sh: GLOBAL install done — applies to every session. Restart/reload Claude Code for it to take effect."
else
  echo "install.sh: done. Restart/reload Claude Code in $TARGET for the hooks to take effect."
fi
