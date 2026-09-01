#!/usr/bin/env bash
# test-component-server-names.sh — a component may not ORDER a bot onto a retired MCP server.
#
# Components (agents-and-prompts/components/*.md) get @-imported into repos' CLAUDE.md/AGENTS.md
# as standing orders. The template layer decides which MCP servers a repo actually wires. Nothing
# tied the two together, and they drifted: BuildingAppleProjects.md commanded "ALWAYS use
# drews-xcode-mcp" and "NEVER use xcodebuild" while the swift-ios template installed the
# xcode-combined aggregator (where that server's build tool is renamed `build`) AND XcodeBuildMCP
# (which IS xcodebuild) into the same repo — one composed install, contradictory orders
# (found live by Jonathan, 2026-09-01, in pot-mhm). This test pins the class: any retired server
# name appearing in a component fails the run, with the file named.
#
# The retired list is data, here in the test, because retirement is a decision recorded in
# tools/lib/templates.json history and tools/tool-templates/facts/ — when a server is retired
# from the templates, add its name here and the run forces every component to catch up.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

COMPONENTS="$HERE/../../agents-and-prompts/components"
assert_dir "$COMPONENTS" "the components directory exists"

# Server names no template wires anymore; a component ordering their use is drift.
RETIRED=(
  "drews-xcode-mcp"     # direct Drew spawn — replaced by the xcode-combined aggregator
  "xcrun mcpbridge"     # direct Apple spawn — per-PID approval anti-pattern, same replacement
)

scan(){ # scan <dir> ; prints offending file:line matches, exits 1 if any
  local dir="$1" found=0
  for name in "${RETIRED[@]}"; do
    if grep -rn -F "$name" "$dir"/*.md 2>/dev/null; then found=1; fi
  done
  [ "$found" -eq 0 ] || { echo "RETIRED SERVER NAME in component" >&2; return 1; }
  return 0
}

if scan "$COMPONENTS"; then
  pass "no component orders a bot onto a retired MCP server"
else
  fail "a component references a retired MCP server (see lines above) — it will misdirect every repo that imports it"
fi

# RED control: a component that DOES name a retired server must be caught, with the right
# diagnostic. Same grep + same diagnostic as scan(), run against a deliberately stale file —
# proves the check reads inside files and matches the multi-word name too.
mkdir -p "$SB/components"
printf '# Fake component\n- ALWAYS use drews-xcode-mcp for builds\n- spawn with xcrun mcpbridge\n' > "$SB/components/Stale.md"
red "a component naming a retired server is caught" 1 "RETIRED SERVER NAME" \
  bash -c 'found=0
    for name in "drews-xcode-mcp" "xcrun mcpbridge"; do
      grep -rn -F "$name" "$1"/*.md && found=1
    done
    [ "$found" -eq 0 ] || { echo "RETIRED SERVER NAME in component" >&2; exit 1; }' _ "$SB/components"

finish
