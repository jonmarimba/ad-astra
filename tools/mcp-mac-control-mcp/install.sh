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
# Dependencies: mac_control_mcp (installed/updated below), claude, gh, shasum
#
# THE APP INSTALL/UPDATE PATH LIVES HERE. Nothing else has one: kicker's setup-mcp.sh (and
# the bundle's verbatim copy) only CHECK for /Applications/MacControlMCP.app and die pointing
# at the releases page — which is how the machine sat on 0.2.6 while upstream shipped 0.8.2
# (found 2026-09-01). Per the repo's cardinal rule the installer pulls the LATEST release
# fresh from the external source and re-running it is the update path. sha256-verified.
# The app is Developer ID-signed (team A3W973JZ49), so its Accessibility/Screen-Recording
# TCC grants should survive same-team updates — if a grant drops after an update, re-add the
# app in System Settings > Privacy & Security.
#
# Usage: ./install.sh --into <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="$HERE/../mcp-bundle"
export PATH="/opt/homebrew/bin:$PATH"

APP="/Applications/MacControlMCP.app"
REPO_GH="AdelElo13/mac-control-mcp"
command -v gh >/dev/null || { echo "mac-control-mcp: FAIL — gh missing. brew install gh" >&2; exit 69; }

LATEST="$(gh api "repos/$REPO_GH/releases/latest" --jq .tag_name)"
[ -n "$LATEST" ] || { echo "mac-control-mcp: FAIL — could not read latest release of $REPO_GH" >&2; exit 69; }
HAVE="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo none)"

if [ "v$HAVE" != "$LATEST" ]; then
  echo "mac-control-mcp: installing MacControlMCP.app $LATEST (have: $HAVE)"
  WORK="$(mktemp -d -t mac-control-mcp)"
  trap 'rm -rf "$WORK"' EXIT
  gh release download "$LATEST" --repo "$REPO_GH" --dir "$WORK" \
    --pattern "MacControlMCP-*-macos-universal.tar.gz" --pattern "*.sha256" \
    || { echo "mac-control-mcp: FAIL — release download" >&2; exit 69; }
  ( cd "$WORK" && shasum -a 256 -c ./*.sha256 ) \
    || { echo "mac-control-mcp: FAIL — sha256 mismatch on downloaded app; NOT installing" >&2; exit 65; }
  tar xzf "$WORK"/MacControlMCP-*-macos-universal.tar.gz -C "$WORK"
  [ -d "$WORK/MacControlMCP.app" ] || { echo "mac-control-mcp: FAIL — archive did not contain MacControlMCP.app" >&2; exit 65; }
  rm -rf "$APP"
  mv "$WORK/MacControlMCP.app" "$APP"
  echo "mac-control-mcp: installed $LATEST -> $APP (running sessions keep the old binary until their server respawns)"
else
  echo "mac-control-mcp: MacControlMCP.app already at latest ($LATEST)"
fi

"$BUNDLE/install.sh" "$@" mac-control-mcp

# DEDUPE against user scope (Claude only — its scopes MERGE, so a project entry beside an
# identical user-scope one serves the same 64 tools twice in every session; found live in
# pot-mhm 2026-09-01). If the user's ~/.claude/.claude.json already spawns this exact
# binary, strip the project entry the bundle just wrote and say so. Qwen/Codex keep their
# project entries: their project scope OVERRIDES rather than merges, so no duplication.
TARGET=""
prev=""
for a in "$@"; do [ "$prev" = "--into" ] && TARGET="$a"; prev="$a"; done
if [ -n "$TARGET" ] && [ -f "$HOME/.claude/.claude.json" ] && [ -f "$TARGET/.mcp.json" ]; then
  python3 - "$TARGET/.mcp.json" "$HOME/.claude/.claude.json" "$APP/Contents/MacOS/MacControlMCP" <<'PY'
import json, sys
proj_path, user_path, binary = sys.argv[1], sys.argv[2], sys.argv[3]
user = json.load(open(user_path)).get("mcpServers", {})
if any(s.get("command") == binary for s in user.values()):
    d = json.load(open(proj_path))
    if d.get("mcpServers", {}).pop("mac-control-mcp", None):
        json.dump(d, open(proj_path, "w"), indent=2); open(proj_path, "a").write("\n")
        print("mac-control-mcp: user scope already runs this binary; SKIPPED the Claude "
              "project entry (scopes merge — it would double every tool). Qwen/Codex "
              "project entries kept.")
PY
fi
exit 0
