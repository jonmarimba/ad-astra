#!/usr/bin/env bash
# ios-simulator — install ONE MCP server, into a given repo.
#
# Drive the iOS Simulator.
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
# Dependencies: node_npx, claude, npm:ios-simulator-mcp, brew:facebook/fb/idb-companion,
# pipx:fb-idb (the `idb` CLI). The server's screenshot tools use simctl, but EVERY
# interaction tool (ui_tap, ui_view, ui_describe_all) shells out to `idb` — without it the
# config installs fine and every real call dies with `spawn idb ENOENT` (found live in
# pot-mhm, 2026-09-01, by the first agent to actually tap something). The companion alone is
# NOT enough: brew's idb-companion ships the daemon, the Python fb-idb package ships the
# `idb` CLI the MCP spawns. pipx installs to ~/.local/bin, which GUI-spawned MCP servers may
# not have on PATH, so the CLI is linked into /opt/homebrew/bin as well.
#
# Usage: ./install.sh --into <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="$HERE/../mcp-bundle"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
if ! command -v idb_companion >/dev/null; then
  echo "ios-simulator: installing idb-companion (interaction tools need it)"
  brew install facebook/fb/idb-companion || { echo "ios-simulator: FAIL — brew install facebook/fb/idb-companion" >&2; exit 69; }
fi
if ! command -v idb >/dev/null; then
  command -v pipx >/dev/null || { echo "ios-simulator: FAIL — pipx missing. brew install pipx" >&2; exit 69; }
  echo "ios-simulator: installing fb-idb (the idb CLI the server spawns)"
  pipx install fb-idb || { echo "ios-simulator: FAIL — pipx install fb-idb" >&2; exit 69; }
fi
# GUI-spawned servers get a minimal PATH; make idb reachable from /opt/homebrew/bin.
[ -x /opt/homebrew/bin/idb ] || ln -sf "$(command -v idb)" /opt/homebrew/bin/idb

exec "$BUNDLE/install.sh" "$@" ios-simulator
