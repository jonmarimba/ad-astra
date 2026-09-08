#!/bin/bash
# install.sh — install claude-safety-hooks into a target repo's .claude/hooks/ and wire
# them into PreToolUse/Bash in .claude/settings.local.json (merged additively, never
# clobbering existing hooks).
#
# Usage:
#   ./install.sh --into /path/to/target-repo [--reap-hint "text naming your reap mechanism"]
#
# What it does:
#   1. Copies no-silent-truncation.sh and no-killing-other-claudes.sh into
#      <target>/.claude/hooks/, executable.
#   2. Seeds <target>/.claude/hooks/no-silent-truncation.watchlist from the .default file
#      HERE, but only if the target doesn't already have one — never overwrites a repo's
#      own tuned watchlist on a re-run.
#   3. If --reap-hint is given, bakes it into the installed no-killing-other-claudes.sh as
#      REAP_MECHANISM_HINT (a sed replace on the installed copy only — this repo's own
#      copy of the hook stays generic).
#   4. Merges PreToolUse/Bash hook entries into <target>/.claude/settings.local.json via
#      jq, additively — an existing PreToolUse/Bash hook list is preserved, and re-running
#      this installer does not duplicate entries already present.
#
# Requires: jq (brew install jq). Re-run any time to update the hook scripts themselves;
# it will refuse to touch a watchlist that already exists.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
REAP_HINT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="$2"; shift 2 ;;
    --reap-hint) REAP_HINT="$2"; shift 2 ;;
    *) echo "install.sh: unknown argument $1" >&2; exit 1 ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "usage: install.sh --into /path/to/target-repo [--reap-hint TEXT]" >&2
  exit 1
fi
if [ ! -d "$TARGET" ]; then
  echo "install.sh: target repo not found: $TARGET" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "install.sh: jq is required (brew install jq)" >&2
  exit 1
fi

HOOKS_DIR="$TARGET/.claude/hooks"
mkdir -p "$HOOKS_DIR"

cp "$HERE/no-silent-truncation.sh" "$HOOKS_DIR/no-silent-truncation.sh"
cp "$HERE/no-killing-other-claudes.sh" "$HOOKS_DIR/no-killing-other-claudes.sh"
chmod +x "$HOOKS_DIR/no-silent-truncation.sh" "$HOOKS_DIR/no-killing-other-claudes.sh"

if [ -n "$REAP_HINT" ]; then
  # Only touch the INSTALLED copy -- this repo's own source stays generic. The default is
  # REAP_MECHANISM_HINT="${REAP_MECHANISM_HINT:-}" on one line; replace just that line.
  esc_hint="$(printf '%s' "$REAP_HINT" | sed -e 's/[\/&]/\\&/g')"
  sed -i '' "s/^REAP_MECHANISM_HINT=\"\${REAP_MECHANISM_HINT:-}\"\$/REAP_MECHANISM_HINT=\"\${REAP_MECHANISM_HINT:-$esc_hint}\"/" \
    "$HOOKS_DIR/no-killing-other-claudes.sh"
fi

WATCHLIST="$HOOKS_DIR/no-silent-truncation.watchlist"
if [ -f "$WATCHLIST" ]; then
  echo "install.sh: leaving existing watchlist in place: $WATCHLIST"
else
  cp "$HERE/no-silent-truncation.watchlist.default" "$WATCHLIST"
  echo "install.sh: seeded a starter watchlist at $WATCHLIST -- edit it to name YOUR search tools"
fi

SETTINGS="$TARGET/.claude/settings.local.json"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

TMP="$(mktemp)"
jq '
  .hooks //= {} |
  .hooks.PreToolUse //= [] |
  # find (or create) the entry whose matcher is "Bash"
  (.hooks.PreToolUse | map(.matcher == "Bash") | index(true)) as $idx |
  if $idx == null then
    .hooks.PreToolUse += [{"matcher": "Bash", "hooks": []}]
  else . end
  | (.hooks.PreToolUse | map(.matcher == "Bash") | index(true)) as $idx2
  | .hooks.PreToolUse[$idx2].hooks as $existing
  | .hooks.PreToolUse[$idx2].hooks =
      ($existing
        + (["$CLAUDE_PROJECT_DIR/.claude/hooks/no-silent-truncation.sh",
            "$CLAUDE_PROJECT_DIR/.claude/hooks/no-killing-other-claudes.sh"]
           | map({"type": "command", "command": .})
           | map(select(. as $new | ($existing | map(.command) | index($new.command)) == null)))
      )
' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

echo "install.sh: wired into $SETTINGS (PreToolUse/Bash, merged additively)"
echo "install.sh: done. Restart/reload Claude Code in $TARGET for the hooks to take effect."
