#!/bin/bash
# xcode-combined-front-run.sh — the actual process launchd supervises for the
# COMBINED instance: Apple's mcpbridge, Drew's drews-xcode-mcp, and
# XcodeBuildMCP behind ONE endpoint, with separate tool prefixes
# (xcode__..., drews__..., xbm__...).
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
export PATH="${ASTRA_PATH:-/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$PATH}"
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
    "xbm": {
      "command": "npx", "args": ["-y", "xcodebuildmcp@latest", "mcp"],
      "block": [
        {"tool": "boot_sim", "why": "NARROW SLICE (Jonathan, 2026-09-01): XcodeBuildMCP joins for coverage, build_run_sim and Xcode-down operation only. Sim lifecycle is ios-simulator/simctl territory, and build_run_sim boots on its own."},
        {"tool": "open_sim", "why": "Narrow slice: sim lifecycle lives elsewhere (ios-simulator, simctl)."},
        {"tool": "build_sim", "why": "Narrow slice: compile-only build overlaps the measured build owner (Drew's, exposed as `build`); build_run_sim is the piece nothing else has."},
        {"tool": "clean", "why": "Narrow slice: drews__clean_project owns clean."},
        {"tool": "discover_projs", "why": "Narrow slice: drews__get_xcode_projects owns on-disk project discovery."},
        {"tool": "install_app_sim", "why": "Narrow slice: ios-simulator's install_app owns this; build_run_sim installs on its own."},
        {"tool": "launch_app_sim", "why": "Narrow slice: ios-simulator's launch_app owns this; build_run_sim launches on its own."},
        {"tool": "stop_app_sim", "why": "Narrow slice: ios-simulator's terminate_app owns this."},
        {"tool": "screenshot", "why": "Narrow slice: drews' and ios-simulator's screenshots own capture."},
        {"tool": "record_sim_video", "why": "Narrow slice: ios-simulator's record_video/stop_recording own video."},
        {"tool": "snapshot_ui", "why": "Apple DeviceInteractionSynthesize returns the current UI hierarchy and screenshot in its device session; Apple owns Xcode device inspection."}
      ]
    },
    "drews": {
      "command": "uvx", "args": ["drews-xcode-mcp"],
      "block": [
        {"tool": "create_project", "why": "Apple XcodeNewProject uses Xcode's template catalog and owns new Xcode project creation."},
        {"tool": "get_project_schemes", "why": "Apple XcodeListSchemes returned the three Work Tool picker schemes; Drew returned dependency schemes too. Apple owns open-workspace schemes."},
        {"tool": "list_run_destinations", "why": "Apple XcodeListRunDestinations identifies the active, eligible picker destinations. Drew returns simulator IDs but not picker eligibility. Apple owns destination selection."},
        {"tool": "get_active_run_destination", "why": "Apple XcodeListRunDestinations includes the active destination. Drew's separate query duplicates that answer."},
        {"tool": "set_run_destination", "why": "Apple owns the Xcode destination family; XcodeSwitchRunDestination changes the selected destination."},
        {"tool": "list_project_tests", "why": "Apple GetTestList returned the same Work Tool test immediately, with enabled status and source location. Drew required a build-for-testing pass."},
        {"tool": "run_project_tests", "why": "Apple owns tests for the open workspace with RunAllTests and RunSomeTests. Drew's run was not measured; XBM test_sim retains prepared-artifact testing."},
        {"tool": "run_project_unmonitored", "why": "Apple RunProject verifies launch and returns a PID and console session in the visible Xcode window. Drew only confirms dispatch."},
        {"tool": "run_project_with_user_interaction", "why": "Apple RunProject owns interactive Xcode runs and avoids Drew's blocking completion dialog."},
        {"tool": "stop_project", "why": "Apple StopProject owns stopping apps launched through the visible Xcode window."},
        {"tool": "take_simulator_screenshot", "why": "The ios-simulator screenshot tool owns simulator pixel capture; Drew's separate capture duplicates it."}
      ],
      "map": [
        {"tool": "build_project", "name": "build", "why": "MEASURED: Drew wins the build overlap; expose it under one canonical name so the model sees a single build tool, not two vendors' names."}
      ]
    }
  }
}
EOF

# The generated file stays strict JSON. Resolve this install's wrapper path after the
# quoted heredoc, so the documentation strings above cannot execute shell syntax.
tmp_info="$(mktemp "$XCODE_MCP_FRONT_HOME/.mcp_info.XXXXXX")"
jq --arg command "$HERE/xcodebuildmcp-run.sh" \
  '.mcpServers.xbm.command = $command | .mcpServers.xbm.args = []' \
  "$XCODE_MCP_FRONT_MCP_INFO" > "$tmp_info" || {
  rm -f "$tmp_info"
  exit 65
}
mv "$tmp_info" "$XCODE_MCP_FRONT_MCP_INFO" || {
  rm -f "$tmp_info"
  exit 74
}

# shellcheck disable=SC1091
. "$HERE/self-preempt.sh"

exec uv run --script "$HERE/daemon.py"
