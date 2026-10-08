#!/usr/bin/env bash
# test-template-members-uninstall.sh — every tool a template installs can be uninstalled.
#
# template.py rolls back a failed install by running each member's uninstall.sh. A member
# without one turns a partial failure into "ROLLBACK FAILED ... has no uninstall.sh" and
# leaves the repo half-installed. mcp-xcode-combined shipped without one; it surfaced on a
# clean-HOME swift-ios install where a later member failed (2026-10-07). This test checks
# the shipped templates, and then proves the uninstaller actually removes what the
# installer wrote, because an uninstall.sh that exits 0 and removes nothing passes a
# file-exists check and fails the user.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need jq "brew install jq"; need python3 "install python3"
TOOLS="$ASTRA_ROOT/tools"

echo "== every member of every template has an uninstall.sh"
members="$(jq -r '.templates | to_entries[] | (.value.tools // [])[]' "$TOOLS/lib/templates.json" | sort -u)"
assert_nonempty "$members" "the template list was read (tautology guard)"
missing=""
# `# astra-scope: machine` tools install once per machine and are never rolled back or
# removed from a repo (template.py reports them as "MACHINE ... install once per machine"),
# so they owe no repo uninstaller.
for m in $members; do
  grep -q '^# astra-scope: machine' "$TOOLS/$m/install.sh" 2>/dev/null && continue
  [ -f "$TOOLS/$m/uninstall.sh" ] || missing="$missing $m"
done
assert_empty "$missing" "no template member lacks an uninstall.sh"
[ -z "$missing" ] || echo "        missing:$missing"

echo "== mcp-xcode-combined: uninstall removes exactly what install wrote"
REPO="$SB/repo"; mkdir -p "$REPO/.codex"
printf '{"mcpServers":{"other":{"type":"http","url":"http://x/mcp"}}}\n' > "$REPO/.mcp.json"
printf '[mcp_servers.keepme]\nurl = "http://k/mcp"\n' > "$REPO/.codex/config.toml"
assert_rc 0 "install" "$TOOLS/mcp-xcode-combined/install.sh" --into "$REPO"
assert_contains "$REPO/.mcp.json" "xcode-combined" "install wrote the Claude entry"
assert_contains "$REPO/.codex/config.toml" "[mcp_servers.xcode-combined]" "install wrote the Codex entry"
if [ -f "$TOOLS/mcp-xcode-combined/uninstall.sh" ]; then
  assert_rc 0 "uninstall" "$TOOLS/mcp-xcode-combined/uninstall.sh" --into "$REPO"
  assert_not_contains "$REPO/.mcp.json" "xcode-combined" "the Claude entry is gone"
  assert_contains "$REPO/.mcp.json" '"other"' "another server's entry survives"
  assert_not_contains "$REPO/.codex/config.toml" "xcode-combined" "the Codex entry is gone"
  assert_contains "$REPO/.codex/config.toml" "[mcp_servers.keepme]" "another Codex server survives"
  jq -e . "$REPO/.mcp.json" >/dev/null 2>&1 && pass ".mcp.json is still valid JSON" || fail ".mcp.json was corrupted"
  # a repo with only our entry: the file we created goes away rather than lingering empty
  R2="$SB/repo2"; mkdir -p "$R2"
  "$TOOLS/mcp-xcode-combined/install.sh" --into "$R2" >/dev/null 2>&1
  "$TOOLS/mcp-xcode-combined/uninstall.sh" --into "$R2" >/dev/null 2>&1
  assert_no_file "$R2/.mcp.json" "a .mcp.json holding only our entry is removed"
  # RED control: an uninstall that touches a repo it never installed into must not invent files
  R3="$SB/repo3"; mkdir -p "$R3"
  "$TOOLS/mcp-xcode-combined/uninstall.sh" --into "$R3" >/dev/null 2>&1
  assert_no_file "$R3/.mcp.json" "uninstalling from an untouched repo creates nothing"
  red "uninstall without --into is refused" 64 "usage" "$TOOLS/mcp-xcode-combined/uninstall.sh"
fi
finish
