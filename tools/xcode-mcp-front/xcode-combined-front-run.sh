#!/bin/bash
# xcode-combined-front-run.sh — the actual process launchd supervises for the
# COMBINED instance: both Apple's mcpbridge AND Drew's drews-xcode-mcp behind
# ONE endpoint, tools prefixed per-upstream (xcode__..., drews__...) so a
# same-named tool from either side can never collide or shadow the other.
#
# All the real logic is in the ONE shared daemon.py (Upstream class handles
# per-upstream connect/reconnect/click, build_server() handles the
# prefix-and-route aggregation when XCODE_MCP_FRONT_UPSTREAMS is set) — this
# script is just the env-var config that selects multi-upstream mode, same
# "one tool, thin per-instance launcher" pattern as the single-upstream
# instance's xcode-mcp-front-run.sh.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"

export XCODE_MCP_FRONT_UPSTREAMS="xcode:1:xcrun:mcpbridge;drews:0:uvx:drews-xcode-mcp"
export XCODE_MCP_FRONT_PORT="${XCODE_MCP_FRONT_PORT:-8767}"
export XCODE_MCP_FRONT_HOME="${XCODE_MCP_FRONT_HOME:-$HOME/.xcode-combined-front}"
export XCODE_MCP_FRONT_SERVER_NAME="xcode-combined-front"

mkdir -p "$XCODE_MCP_FRONT_HOME"
PORT="$XCODE_MCP_FRONT_PORT"

# shellcheck disable=SC1091
. "$HERE/self-preempt.sh"

exec uv run --script "$HERE/daemon.py"
