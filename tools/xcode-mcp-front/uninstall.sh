#!/usr/bin/env bash
# uninstall.sh — dis-integrate xcode-mcp-front: stop the daemon if running, remove
# its state dir (~/.xcode-mcp-front: pidfile, log). uv itself is foundational, kept.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "xcode-mcp-front dis-integrate:"
if "$HERE/xcode-mcp-front" status 2>/dev/null | grep -q "^running"; then
  echo "  stopping running daemon first"
  "$HERE/xcode-mcp-front" stop
fi
uc_rm_state "${XCODE_MCP_FRONT_HOME:-$HOME/.xcode-mcp-front}" "xcode-mcp-front state dir (pidfile, log)"
uc_keep uv "foundational script runner (shared by many tools)"
echo "done."
