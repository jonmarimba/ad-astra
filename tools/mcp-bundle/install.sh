#!/usr/bin/env bash
# mcp-bundle/install.sh — install the kicker MCP server set INTO A GIVEN REPO.
#
# Usage:
#   ./install.sh --into <repo>                 # all servers
#   ./install.sh --into <repo> xcode ios-simulator   # just these
#   ./install.sh --into <repo> --list          # what would be installed
#
# WHAT THIS IS
# ------------
# The first astra tool that is really a BUNDLE of tools. setup-mcp.sh came from
# js-llmKicker/scripts/setup-mcp.sh and is copied here VERBATIM on purpose —
# astra-fied as-is, not refactored. It configures the same MCP server set for
# three different agents that each keep config in a different place:
#
#   Claude Code  ->  <repo>/.mcp.json          (via `claude mcp add --scope project`)
#   Qwen Code    ->  <repo>/.qwen/settings.json
#   Codex CLI    ->  <repo>/.codex/config.toml
#
# Servers in the bundle: mac-control-mcp, xcode-mcp-server, xcode, ios-simulator,
# XcodeBuildMCP, mobile-mcp, kickerd.
#
# WHERE THIS IS GOING (not built yet — do not pretend otherwise)
# --------------------------------------------------------------
# Jonathan's plan, 2026-08-18: eventually these become many small composable
# tools plus TEMPLATES that install a set fit for a kind of project — the
# Maharam repos want the Swift/iOS group plus the writing tools; the legal repos
# want the pdf-to-text group plus the writing tools. This file is the crude
# first step: one bundle, installed per-repo. The decomposition comes later.
#
# THE RULE THIS EXISTS TO ENFORCE
# -------------------------------
# NOTHING FROM ASTRA IS EVER INSTALLED GLOBALLY. No ~/.claude, no ~/.agents, no
# user-scope MCP. Every write lands inside the target repo. setup-mcp.sh already
# honours this (it only ever uses --scope project and repo-relative paths), and
# this wrapper ASSERTS it rather than trusting it: the target must be a real
# directory, and it must not be a home-level config directory.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo> [servers...]" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "no such directory: $TARGET" >&2; exit 66; }
TARGET="$(cd "$TARGET" && pwd -P)"   # -P resolves symlinks; js-speedway is one

# Refuse anything that is not a project checkout. This is the guard that keeps a
# future careless run from recreating the global installs we just removed.
case "$TARGET" in
  "$HOME"|"$HOME/.claude"*|"$HOME/.agents"*|"$HOME/.config"*|"$HOME/Library"*)
    echo "REFUSING: $TARGET is a home/global location." >&2
    echo "  Astra tools install per-repo only. Point --into at a project checkout." >&2
    exit 78 ;;
esac
[ -d "$TARGET/.git" ] || echo "note: $TARGET has no .git — installing anyway, but this is usually a mistake." >&2

echo "installing MCP bundle into: $TARGET"
cd "$TARGET"
if [ ${#ARGS[@]} -gt 0 ]; then
  "$HERE/setup-mcp.sh" --install "${ARGS[@]}"
else
  "$HERE/setup-mcp.sh" --install
fi

echo
echo "wrote (repo-local only):"
for f in .mcp.json .qwen/settings.json .codex/config.toml; do
  [ -e "$TARGET/$f" ] && echo "  $TARGET/$f"
done
