#!/bin/bash
# xcode27-combined-front-run.sh — the Drew + Xcode 27 BETA aggregator, sibling of
# xcode-combined-front-run.sh (which fronts Drew + Xcode 26.6). Same daemon.py, same
# generic aggregator; the only differences are which mcpbridge it fronts (the beta's,
# via DEVELOPER_DIR) and which Xcode the require_xcode quirk + clicker target
# (Xcode-beta.app, so it never fights the 26.6 instance for the wrong approval dialog).
#
# STARTS AS PURE PASSTHROUGH on purpose: Xcode 27's tool list is not yet known (its
# bridge only serves once the beta's components are installed), so there is no measured
# collision map to apply. Mirror the 26.6 workflow — serve both surfaces prefixed, pull
# the 27 tool list, MEASURE each real overlap by running both tools, THEN write the
# fact-based sieve/map for 27 specifically (its collisions may differ from 26.6's:
# 26.5->26.6 was already non-additive, so 26.6->27 must be measured, not assumed).
#
# Until the beta bridge serves, the daemon's 1.4 behaviour serves Drew's tools and marks
# xcode27 unavailable; it picks the Xcode half up the moment the beta is ready.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"

BETA_DEVDIR="/Applications/Xcode-beta.app/Contents/Developer"
export XCODE_MCP_FRONT_PORT="${XCODE_MCP_FRONT_PORT:-8768}"
export XCODE_MCP_FRONT_HOME="${XCODE_MCP_FRONT_HOME:-$HOME/.xcode27-combined-front}"
export XCODE_MCP_FRONT_SERVER_NAME="xcode27-combined-front"
# require_xcode and the clicker must target the BETA, not /Applications/Xcode.app.
export XCODE_MCP_FRONT_XCODE_APP_PATH="/Applications/Xcode-beta.app"
# Clicker ON: this .app now HOLDS an Automation TCC grant (Jonathan approved it
# 2026-08-31), so the clicker's osascript is authorized to answer Xcode 27's approval
# dialog hands-free. Combined with the daemon's first-approval HOLD (one list_tools kept
# in flight, never cancelled), the single dialog stays up until the clicker accepts it
# once — no withdraw-and-re-ask storm. Set XCODE_MCP_FRONT_AUTO_ALLOW=0 in the environment
# to force a human/mac-control answer instead (e.g. if the grant is ever revoked).
export XCODE_MCP_FRONT_AUTO_ALLOW="${XCODE_MCP_FRONT_AUTO_ALLOW:-1}"
export XCODE_MCP_FRONT_CONNECT_TIMEOUT_S="${XCODE_MCP_FRONT_CONNECT_TIMEOUT_S:-120}"

mkdir -p "$XCODE_MCP_FRONT_HOME"
PORT="$XCODE_MCP_FRONT_PORT"

# mcpbridge connects to the xcode-select'd Xcode by DEFAULT, which is 26.6, not the
# beta — its --help documents MCP_XCODE_PID to override that with a specific Xcode PID.
# DEVELOPER_DIR only picks the beta's mcpbridge BINARY, not which Xcode it talks to.
# Resolve the running Xcode-beta's PID and pin the bridge to it. (Xcode.app and
# Xcode-beta.app share the process name and bundle id, so match the full binary path.)
BETA_PID="$(pgrep -f '^/Applications/Xcode-beta.app/Contents/MacOS/Xcode$' | head -1)"

export XCODE_MCP_FRONT_MCP_INFO="$XCODE_MCP_FRONT_HOME/_mcp_info.json"
cat > "$XCODE_MCP_FRONT_MCP_INFO" <<EOF
{
  "mcpServers": {
    "xcode27": {
      "command": "$BETA_DEVDIR/usr/bin/mcpbridge", "args": [],
      "env": {"DEVELOPER_DIR": "$BETA_DEVDIR", "MCP_XCODE_PID": "$BETA_PID"},
      "quirks": ["require_xcode"],
      "block": [
        {"tool": "BuildProject", "why": "MEASURED 2026-09-01 on GoalsTool.xcworkspace (facts/xcode27-collisions.md): built OK in 25s but errors-only + log path, ZERO warnings inline; Drew's build_project surfaced 13 real warnings with file:line on the same build. Drew owns build — unchanged from 26.6."},
        {"tool": "GetBuildLog", "why": "MEASURED 2026-09-01: hung >8 minutes after a successful build and broke the connection; Drew's get_build_results returned instantly with per-file warnings plus rebuild analysis. Worse than 26.6's instant-empty. Drew owns build diagnostics."}
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
        {"tool": "get_app_bundle_id", "why": "Narrow slice: plumbing helper outside the kept loop."},
        {"tool": "get_sim_app_path", "why": "Narrow slice: plumbing helper outside the kept loop."},
        {"tool": "install_app_sim", "why": "Narrow slice: ios-simulator's install_app owns this; build_run_sim installs on its own."},
        {"tool": "launch_app_sim", "why": "Narrow slice: ios-simulator's launch_app owns this; build_run_sim launches on its own."},
        {"tool": "stop_app_sim", "why": "Narrow slice: ios-simulator's terminate_app owns this."},
        {"tool": "list_schemes", "why": "Narrow slice: scheme listing owned elsewhere on this surface."},
        {"tool": "list_sims", "why": "Narrow slice: drews__list_booted_simulators and ios-simulator cover sims."},
        {"tool": "screenshot", "why": "Narrow slice: drews' and ios-simulator's screenshots own capture."},
        {"tool": "record_sim_video", "why": "Narrow slice: ios-simulator's record_video/stop_recording own video."},
        {"tool": "show_build_settings", "why": "Narrow slice: build-settings reads stay with the Xcode-side owners."},
        {"tool": "snapshot_ui", "why": "Narrow slice: idb/ios-simulator ui_describe_all owns semantic UI snapshots."}
      ]
    },
    "drews": {
      "command": "uvx", "args": ["drews-xcode-mcp"],
      "block": [
        {"tool": "get_project_schemes", "why": "MEASURED 2026-09-01 on GoalsTool.xcworkspace: returned ~115 schemes of every Pod/dependency as flat text with duplicates; xcode27's XcodeListSchemes returned the 3 real picker schemes, structured, active flagged. xcode27 owns schemes (new in 27 — this was Drew's-only under 26.6)."},
        {"tool": "list_run_destinations", "why": "MEASURED 2026-09-01: exhaustive UDID dump with no active flag; xcode27's XcodeListRunDestinations mirrors the Xcode picker with isActive/isEligible. xcode27 owns destinations. Simulator-by-UDID work stays with list_booted_simulators."},
        {"tool": "get_active_run_destination", "why": "MEASURED 2026-09-01: errored on the real workspace ('Unexpected destination format: dvtdevice-DVTiPhonePlaceholder-iphoneos'); xcode27 reports the active destination inline in XcodeListRunDestinations."},
        {"tool": "set_run_destination", "why": "Destination family goes to xcode27 with the two measured wins above; a lone Drew's setter beside Apple's list/active would split one capability across vendors. XcodeSwitchRunDestination itself is UNMEASURED — if it fails in practice, unblock this."},
        {"tool": "list_project_tests", "why": "MEASURED 2026-09-01: errored on GoalsTool ('Could not find a buildable run destination for scheme Rx (Playground)') — its Pod-noise scheme enumeration poisons test listing; xcode27's GetTestList answered structured and honest (0 tests in scheme). Same direction as the 26.6 fact (facts/tests.md)."},
        {"tool": "run_project_tests", "why": "Test family goes to xcode27 (RunAllTests/RunSomeTests) with the list_project_tests failure above; 26.6 CAVEAT for path-based .xcodeproj workflows still applies (facts/tests.md)."}
      ],
      "map": [
        {"tool": "build_project", "name": "build", "why": "MEASURED: Drew wins the build overlap on the real Maharam workspace; expose one canonical build tool, same as the 26.6 surface."}
      ]
    }
  }
}
EOF

# self-preempt only if that script exists beside us (matches the 26.6 launcher pattern)
[ -f "$HERE/self-preempt.sh" ] && . "$HERE/self-preempt.sh"

exec uv run --script "$HERE/daemon.py"
