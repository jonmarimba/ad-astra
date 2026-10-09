#!/bin/bash
# Only XcodeBuildMCP sees this open shim. Other MCP upstreams use normal macOS routing.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export PATH="$here/xcodebuildmcp-bin:$PATH"
exec npx -y xcodebuildmcp@latest mcp "$@"
