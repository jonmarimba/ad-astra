#!/usr/bin/env bash
# axe — install the AXe CLI (cameroncooke/axe): Apple Accessibility-API driving for the
# iOS Simulator from plain Bash. `axe describe-ui` (AX tree as text), `axe tap --id|--label`,
# `axe type`, `axe swipe`, `axe screenshot`, `axe list-simulators`. https://www.axe-cli.com/
#
# This is a CLI, not an MCP server: nothing is written into the target repo's .mcp.json.
# The doctrine for WHEN to reach for it (ad-hoc probes by identifier; promote stable flows
# to XCUITest) is the ios-ui-driving skill, installed separately by the same template.
#
# Kicker proved it by effect (js-llmKicker DEVLOG 2026-06-18): after accessibility ids were
# added, AXe drove the full SSH-connect flow 100% by identifier, zero coordinates — fixing a
# real dropped-first-character failure the coordinate path had caused.
#
# Dependencies: brew. Installs system-level (a CLI has no per-repo home); the --into arg is
# accepted for template-installer uniformity and used only to validate the target exists.
#
# Usage: ./install.sh --into <repo>
set -uo pipefail
export PATH="/opt/homebrew/bin:$PATH"

TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="${2:-}"; shift 2 ;;
    *) echo "axe: unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "axe: no such directory: $TARGET" >&2; exit 66; }
command -v brew >/dev/null || { echo "axe: FAIL — brew missing" >&2; exit 69; }

if ! command -v axe >/dev/null; then
  echo "axe: installing cameroncooke/axe/axe"
  brew install cameroncooke/axe/axe || { echo "axe: FAIL — brew install cameroncooke/axe/axe" >&2; exit 69; }
else
  # install == update, per the repo rule: pull the latest from the external source.
  brew upgrade cameroncooke/axe/axe 2>/dev/null || true
fi
axe --version >/dev/null 2>&1 || command -v axe >/dev/null || { echo "axe: FAIL — installed but not on PATH" >&2; exit 69; }
echo "axe: $(command -v axe) ready"
exit 0
