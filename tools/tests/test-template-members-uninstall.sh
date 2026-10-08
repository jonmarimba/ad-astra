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
  # all three agents get the entry, creating each file when it is missing, and uninstall removes
  # exactly that: the first install used to leave Codex and Qwen without Xcode (found 2026-10-08)
  R4="$SB/repo4"; mkdir -p "$R4"
  "$TOOLS/mcp-xcode-combined/install.sh" --into "$R4" >/dev/null 2>&1
  assert_eq "http://127.0.0.1:8767/mcp" "$(jq -r '.mcpServers["xcode-combined"].url' "$R4/.mcp.json")" "a fresh repo gets the Claude entry"
  assert_eq "http://127.0.0.1:8767/mcp" "$(jq -r '.mcpServers["xcode-combined"].httpUrl' "$R4/.qwen/settings.json")" "a fresh repo gets the Qwen entry, in Qwen's httpUrl shape"
  assert_contains "$R4/.codex/config.toml" "[mcp_servers.xcode-combined]" "a fresh repo gets the Codex entry, with no config file there before"
  "$TOOLS/mcp-xcode-combined/install.sh" --into "$R4" >/dev/null 2>&1
  assert_eq 1 "$(grep -c 'mcp_servers.xcode-combined' "$R4/.codex/config.toml")" "installing twice does not duplicate the Codex entry"
  mkdir -p "$SB/repo5/.qwen"; printf '{"mcpServers":{"keep":{"command":"x"}},"theme":"dark"}\n' > "$SB/repo5/.qwen/settings.json"
  "$TOOLS/mcp-xcode-combined/install.sh" --into "$SB/repo5" >/dev/null 2>&1
  "$TOOLS/mcp-xcode-combined/uninstall.sh" --into "$SB/repo5" >/dev/null 2>&1
  assert_eq '{"mcpServers":{"keep":{"command":"x"}},"theme":"dark"}' "$(jq -c . "$SB/repo5/.qwen/settings.json")" "uninstall restores a Qwen config with other settings exactly"
  "$TOOLS/mcp-xcode-combined/uninstall.sh" --into "$R4" >/dev/null 2>&1
  assert_no_file "$R4/.mcp.json" "uninstall removes the .mcp.json it created"
  assert_no_file "$R4/.qwen/settings.json" "and the Qwen settings it created"
  assert_no_file "$R4/.codex/config.toml" "and the Codex config it created"
  # RED control: an uninstall that touches a repo it never installed into must not invent files
  R3="$SB/repo3"; mkdir -p "$R3"
  "$TOOLS/mcp-xcode-combined/uninstall.sh" --into "$R3" >/dev/null 2>&1
  assert_no_file "$R3/.mcp.json" "uninstalling from an untouched repo creates nothing"
  red "uninstall without --into is refused" 64 "usage" "$TOOLS/mcp-xcode-combined/uninstall.sh"
fi
finish
