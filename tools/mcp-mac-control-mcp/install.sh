#!/usr/bin/env bash
# mac-control-mcp — install ONE MCP server, into a given repo.
#
# Drive macOS: windows, clicks, keys, screen capture, accessibility tree.
#
# Split out of tools/mcp-bundle on 2026-08-18. The bundle came over from kicker
# as a single 727-line script that installed seven servers together; Jonathan's
# plan is many small composable tools plus templates that install a set fit for a
# kind of project. This is one of those small tools.
#
# It delegates to the bundle rather than duplicating its logic. The bundle
# already knows how to write this server's entry for all three agents that keep
# config in different places — Claude Code (<repo>/.mcp.json via
# `claude mcp add --scope project`), Qwen (<repo>/.qwen/settings.json), Codex
# (<repo>/.codex/config.toml). Copying that per-server would be seven chances to
# drift, which is the exact disease the tool registry exists to cure.
#
# Dependencies: mac_control_mcp, claude
#
# Usage: ./install.sh --into <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="$HERE/../mcp-bundle"
exec "$BUNDLE/install.sh" "$@" mac-control-mcp
