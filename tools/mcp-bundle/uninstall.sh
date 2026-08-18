#!/usr/bin/env bash
# mcp-bundle/uninstall.sh — remove the MCP server set FROM A GIVEN REPO.
#
# Usage:
#   ./uninstall.sh --into <repo>                # all servers
#   ./uninstall.sh --into <repo> xcode          # just these
#
# setup-mcp.sh's `--disable` is already a true removal rather than a flag flip:
# it runs `claude mcp remove --scope project`, prunes the entry from
# .qwen/settings.json and .codex/config.toml, and cleans up the files when they
# are left empty. This wrapper gives that the name it deserves and applies the
# same "must be a repo, never a home directory" guard as install.sh, so an
# uninstall cannot wander into ~/.claude either.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

[ -n "$TARGET" ] || { echo "usage: uninstall.sh --into <repo> [servers...]" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "no such directory: $TARGET" >&2; exit 66; }
TARGET="$(cd "$TARGET" && pwd -P)"

case "$TARGET" in
  "$HOME"|"$HOME/.claude"*|"$HOME/.agents"*|"$HOME/.config"*|"$HOME/Library"*)
    echo "REFUSING: $TARGET is a home/global location." >&2; exit 78 ;;
esac

echo "removing MCP bundle from: $TARGET"
cd "$TARGET"
if [ ${#ARGS[@]} -gt 0 ]; then
  "$HERE/setup-mcp.sh" --disable "${ARGS[@]}"
else
  "$HERE/setup-mcp.sh" --disable
fi

echo
echo "remaining config in $TARGET:"
found=0
for f in .mcp.json .qwen/settings.json .codex/config.toml; do
  [ -e "$TARGET/$f" ] && { echo "  still present: $f"; found=1; }
done
[ "$found" -eq 0 ] && echo "  none — clean"
