#!/bin/bash
# xcode-combined-front-run.sh — the actual process launchd supervises for the
# COMBINED instance: both Apple's mcpbridge AND Drew's drews-xcode-mcp behind
# ONE endpoint, tools prefixed per-upstream (xcode__..., drews__...) so a
# same-named tool from either side can never collide or shadow the other.
#
# All the real logic is in the ONE shared daemon.py (Upstream class handles
# per-upstream connect/reconnect/click, build_server() handles the
# prefix-and-route aggregation when XCODE_MCP_FRONT_MCP_INFO points at a
# config file) — this script is just the per-instance config, same "one
# tool, thin per-instance launcher" pattern as the single-upstream
# instance's xcode-mcp-front-run.sh.
#
# The upstream set is a _mcp_info.json in the Claude Code shape (validated
# by mcp_config.py; the old XCODE_MCP_FRONT_UPSTREAMS colon format is a
# startup error since tool-templates increment 1.2). The underscore file is
# MACHINE-OWNED, mogenerator-style: rewritten on every launch, never edited
# by hand — a per-repo change belongs in the template layer, not here.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
export XCODE_MCP_FRONT_PORT="${XCODE_MCP_FRONT_PORT:-8767}"
export XCODE_MCP_FRONT_HOME="${XCODE_MCP_FRONT_HOME:-$HOME/.xcode-combined-front}"
export XCODE_MCP_FRONT_SERVER_NAME="xcode-combined-front"

mkdir -p "$XCODE_MCP_FRONT_HOME"
PORT="$XCODE_MCP_FRONT_PORT"

export XCODE_MCP_FRONT_MCP_INFO="$XCODE_MCP_FRONT_HOME/_mcp_info.json"
cat > "$XCODE_MCP_FRONT_MCP_INFO" <<'EOF'
{
  "mcpServers": {
    "xcode": {
      "command": "xcrun", "args": ["mcpbridge"], "quirks": ["require_xcode"],
      "block": [
        {"tool": "BuildProject", "why": "MEASURED 2026-08-31 (tool-templates/facts/build.md): Drew's build_project returns inline warning counts+text and builds any path; Apple's is errors-only + log path, open-tab only. Drew owns build."},
        {"tool": "GetBuildLog", "why": "MEASURED (facts/build-diagnostics.md): Apple's GetBuildLog returned empty entries (totalFound 0); Drew's get_build_results/get_build_errors give structured per-file warning analysis. Drew owns build diagnostics."}
      ]
    },
    "drews": {
      "command": "uvx", "args": ["drews-xcode-mcp"],
      "block": [
        {"tool": "list_project_tests", "why": "MEASURED (facts/tests.md): Apple's GetTestList gives structured test-plan results and works on the open workspace incl SwiftPM; Drew needs a configured .xcodeproj test target. Apple owns test-listing. (CAVEAT in facts/tests.md for path-based .xcodeproj workflows.)"},
        {"tool": "run_project_tests", "why": "MEASURED (facts/tests.md): Apple owns test-running for the open workspace; see the CAVEAT for path-based .xcodeproj workflows."}
      ],
      "map": [
        {"tool": "build_project", "name": "build", "why": "MEASURED: Drew wins the build overlap; expose it under one canonical name so the model sees a single build tool, not two vendors' names."}
      ]
    }
  }
}
EOF

# shellcheck disable=SC1091
. "$HERE/self-preempt.sh"

exec uv run --script "$HERE/daemon.py"
