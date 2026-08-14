#!/usr/bin/env bash
# uninstall.sh — dis-integrate xcode-mcp-front: unload the launchd job, remove
# its plist, remove state (log, pidfile, config). Leaves XcodeMCPFront.app in
# place by default — it holds a TCC grant that's expensive to re-grant, and
# deleting it isn't reversible; pass --deps to remove it too.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "xcode-mcp-front dis-integrate:"

"$HERE/xcode-mcp-front" launchd-uninstall

if "$HERE/xcode-mcp-front" status 2>/dev/null | grep -q "^running"; then
  echo "  stopping manual-mode instance too"
  "$HERE/xcode-mcp-front" stop
fi

uc_rm_state "${XCODE_MCP_FRONT_HOME:-$HOME/.xcode-mcp-front}" "xcode-mcp-front state dir (log, pidfile, config)"
uc_keep uv "foundational script runner (shared by many tools)"

if [ "${UNINSTALL_DEPS:-0}" = "1" ]; then
  if [ -e "$HERE/XcodeMCPFront.app" ]; then
    echo "  --deps: removing XcodeMCPFront.app (its TCC grant is gone with it — a reinstall will need re-granting)"
    rm -rf "$HERE/XcodeMCPFront.app" "$HERE/xcodemcpfront_launch.sh"
  fi
else
  [ -e "$HERE/XcodeMCPFront.app" ] && echo "  keeping XcodeMCPFront.app (holds a TCC grant) — pass --deps to remove it too"
fi

echo "done."
