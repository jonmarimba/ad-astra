#!/usr/bin/env bash
# test-mcp-xcode-combined-config.sh — the xcode-combined entry in all four agents' project configs,
# and that re-running the installer with a new URL moves all four to it. Codex used to keep the old
# URL when its table already existed, so a changed XCODE_COMBINED_URL updated two agents of three.
#
# The real installer, real files in a sandbox repo; no daemon is started.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
need jq "brew install jq"
need python3 "xcode-select --install"
INST="$ASTRA_ROOT/tools/mcp-xcode-combined/install.sh"
UNINST="$ASTRA_ROOT/tools/mcp-xcode-combined/uninstall.sh"

REPO="$SB/repo"; mkdir -p "$REPO/.codex" "$REPO/.qwen" "$REPO/.gemini"
printf '{"mcpServers":{"xcode":{"command":"xcrun","args":["mcpbridge"]},"xcode-mcp-front":{"type":"http","url":"http://127.0.0.1:8765/mcp"},"other":{"type":"http","url":"http://127.0.0.1:1/other"}}}\n' > "$REPO/.mcp.json"
printf '{"mcpServers":{"XcodeBuildMCP":{"command":"npx","args":["xcodebuildmcp"]},"other":{"httpUrl":"http://127.0.0.1:1/other"}}}\n' > "$REPO/.qwen/settings.json"
printf '{"mcpServers":{"xcode-mcp-server":{"command":"uvx"},"other":{"httpUrl":"http://127.0.0.1:1/other"}}}\n' > "$REPO/.gemini/settings.json"
# a Codex config that already holds other tables, both before and after ours
printf '[mcp_servers.other]\nurl = "http://127.0.0.1:1/other"\n\n[mcp_servers.xcode-mcp-server]\ncommand = "uvx"\n\n[mcp_servers.xcode-mcp-server.env]\nDEBUG = "1"\n\n[mcp_servers.xcode-combined]\nurl = "http://127.0.0.1:1/stale"\n\n[mcp_servers.after]\nurl = "http://127.0.0.1:2/after"\n' > "$REPO/.codex/config.toml"

echo "== first install overrides a stale entry"
XCODE_COMBINED_URL="http://127.0.0.1:9001/mcp" bash "$INST" --into "$REPO" > "$SB/i1.out" 2>&1
assert_eq 0 "$?" "install succeeds"
assert_eq "http://127.0.0.1:9001/mcp" "$(jq -r '.mcpServers["xcode-combined"].url' "$REPO/.mcp.json")" "Claude's entry has the URL"
assert_eq "http://127.0.0.1:9001/mcp" "$(jq -r '.mcpServers["xcode-combined"].httpUrl' "$REPO/.qwen/settings.json")" "Qwen's entry has the URL"
assert_eq "http://127.0.0.1:9001/mcp" "$(jq -r '.mcpServers["xcode-combined"].httpUrl' "$REPO/.gemini/settings.json")" "Gemini's entry has the URL"
assert_eq 'false' "$(jq -r '.mcpServers | has("xcode") or has("xcode-mcp-front")' "$REPO/.mcp.json")" "Claude's direct and old front entries are gone"
assert_eq 'false' "$(jq -r '.mcpServers | has("XcodeBuildMCP")' "$REPO/.qwen/settings.json")" "Qwen's direct build entry is gone"
assert_eq 'false' "$(jq -r '.mcpServers | has("xcode-mcp-server")' "$REPO/.gemini/settings.json")" "Gemini's direct Drew entry is gone"
assert_eq 'http://127.0.0.1:1/other' "$(jq -r '.mcpServers.other.url' "$REPO/.mcp.json")" "Claude's unrelated entry survives"
assert_eq 'http://127.0.0.1:1/other' "$(jq -r '.mcpServers.other.httpUrl' "$REPO/.qwen/settings.json")" "Qwen's unrelated entry survives"
assert_eq 'http://127.0.0.1:1/other' "$(jq -r '.mcpServers.other.httpUrl' "$REPO/.gemini/settings.json")" "Gemini's unrelated entry survives"
if grep -Fq '[mcp_servers.xcode-mcp-server]' "$REPO/.codex/config.toml"; then fail "Codex still has the direct Xcode entry"; else pass "Codex's direct entry is gone"; fi
if grep -Fq '[mcp_servers.xcode-mcp-server.env]' "$REPO/.codex/config.toml"; then fail "Codex still has the direct Xcode environment"; else pass "Codex's direct environment is gone"; fi
got="$(awk '/^\[mcp_servers.xcode-combined\]/{f=1;next} /^\[/{f=0} f && /^url/' "$REPO/.codex/config.toml")"
assert_eq 'url = "http://127.0.0.1:9001/mcp"' "$got" "Codex's entry replaced the stale URL"
assert_contains "$REPO/.codex/config.toml" 'url = "http://127.0.0.1:1/other"' "RED: the table before ours is untouched"
assert_contains "$REPO/.codex/config.toml" 'url = "http://127.0.0.1:2/after"' "RED: the table after ours is untouched"

echo "== a second install with a new URL moves all four"
XCODE_COMBINED_URL="http://127.0.0.1:9002/mcp" bash "$INST" --into "$REPO" > "$SB/i2.out" 2>&1
assert_eq "http://127.0.0.1:9002/mcp" "$(jq -r '.mcpServers["xcode-combined"].url' "$REPO/.mcp.json")" "Claude moved"
assert_eq "http://127.0.0.1:9002/mcp" "$(jq -r '.mcpServers["xcode-combined"].httpUrl' "$REPO/.qwen/settings.json")" "Qwen moved"
assert_eq "http://127.0.0.1:9002/mcp" "$(jq -r '.mcpServers["xcode-combined"].httpUrl' "$REPO/.gemini/settings.json")" "Gemini moved"
got="$(awk '/^\[mcp_servers.xcode-combined\]/{f=1;next} /^\[/{f=0} f && /^url/' "$REPO/.codex/config.toml")"
assert_eq 'url = "http://127.0.0.1:9002/mcp"' "$got" "Codex moved too"
assert_eq 1 "$(grep -c '^\[mcp_servers.xcode-combined\]' "$REPO/.codex/config.toml" | tr -d ' ')" "and there is still exactly one table for it"

echo "== a first install retires legacy Codex entries"
FIRST="$SB/first"; mkdir -p "$FIRST/.codex"
printf '[mcp_servers.xcode]\ncommand = "xcrun"\n\n[mcp_servers.other]\nurl = "http://127.0.0.1:1/other"\n' > "$FIRST/.codex/config.toml"
bash "$INST" --into "$FIRST" > "$SB/first.out" 2>&1
assert_eq 0 "$?" "first install succeeds"
if grep -Fq '[mcp_servers.xcode]' "$FIRST/.codex/config.toml"; then fail "first install kept a direct Xcode table"; else pass "first install removed the direct table"; fi
assert_contains "$FIRST/.codex/config.toml" '[mcp_servers.xcode-combined]' "first install added the combined table"
assert_contains "$FIRST/.codex/config.toml" '[mcp_servers.other]' "first install preserved an unrelated table"

echo "== uninstall removes all four and leaves the other tables"
bash "$UNINST" --into "$REPO" > "$SB/u.out" 2>&1
assert_eq 0 "$?" "uninstall succeeds"
if [ ! -e "$REPO/.mcp.json" ]; then pass "Claude's entry is gone (the file it created is removed with it)"
else assert_eq "null" "$(jq '.mcpServers["xcode-combined"]' "$REPO/.mcp.json")" "Claude's entry is gone"; fi
assert_eq "null" "$(jq '.mcpServers["xcode-combined"]' "$REPO/.gemini/settings.json")" "Gemini's entry is gone"
assert_eq 'http://127.0.0.1:1/other' "$(jq -r '.mcpServers.other.httpUrl' "$REPO/.gemini/settings.json")" "Gemini's unrelated entry survives uninstall"
if grep -q 'xcode-combined' "$REPO/.codex/config.toml"; then fail "Codex still has the entry"; else pass "Codex's entry is gone"; fi
assert_contains "$REPO/.codex/config.toml" 'url = "http://127.0.0.1:2/after"' "the table after ours survives uninstall"
finish
