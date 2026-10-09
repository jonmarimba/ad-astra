#!/usr/bin/env bash
# The legacy bundle's default must install the combined front and retire direct Xcode servers.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"
need jq "brew install jq"
need zsh "ships with macOS"
need python3 "xcode-select --install"
need node "brew install node"
need npx "brew install node"

REPO="$SB/repo"
mkdir -p "$REPO/bin" "$REPO/.qwen" "$REPO/.gemini" "$REPO/.codex" "$SB/MacControlMCP.app/Contents/MacOS"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/MacControlMCP.app/Contents/MacOS/MacControlMCP"
chmod +x "$SB/MacControlMCP.app/Contents/MacOS/MacControlMCP"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$MCP_TEST_CALLS"\n' > "$REPO/bin/claude"
printf '#!/usr/bin/env bash\nprintf "1.0.0\\n"\n' > "$REPO/bin/npm"
chmod +x "$REPO/bin/claude" "$REPO/bin/npm"
printf '{"mcpServers":{"xcode":{"command":"xcrun"},"other":{"type":"http","url":"http://127.0.0.1:1/other"}}}\n' > "$REPO/.mcp.json"
printf '{"mcpServers":{"XcodeBuildMCP":{"command":"npx"}}}\n' > "$REPO/.qwen/settings.json"
printf '{"mcpServers":{"xcode-mcp-server":{"command":"uvx"}}}\n' > "$REPO/.gemini/settings.json"
printf '[mcp_servers.xcode]\ncommand = "xcrun"\n\n[mcp_servers.other]\nurl = "http://127.0.0.1:1/other"\n' > "$REPO/.codex/config.toml"

echo "== default bundle install"
(
  cd "$REPO"
  PATH="$REPO/bin:$PATH" MAC_CONTROL_APP="$SB/MacControlMCP.app" MCP_TEST_CALLS="$SB/claude-calls.txt" "$ASTRA_ROOT/tools/mcp-bundle/setup-mcp.sh" --install
) > "$SB/install.out" 2>&1
assert_eq 0 "$?" "default install succeeds"
assert_eq 'http://127.0.0.1:8767/mcp' "$(jq -r '.mcpServers["xcode-combined"].url' "$REPO/.mcp.json")" "Claude gets the combined front"
assert_eq 'false' "$(jq -r '.mcpServers | has("xcode")' "$REPO/.mcp.json")" "Claude's direct bridge is gone"
assert_eq 'http://127.0.0.1:8767/mcp' "$(jq -r '.mcpServers["xcode-combined"].httpUrl' "$REPO/.qwen/settings.json")" "Qwen gets the combined front"
assert_eq 'false' "$(jq -r '.mcpServers | has("XcodeBuildMCP")' "$REPO/.qwen/settings.json")" "Qwen's direct build server is gone"
assert_eq 'http://127.0.0.1:8767/mcp' "$(jq -r '.mcpServers["xcode-combined"].httpUrl' "$REPO/.gemini/settings.json")" "Gemini gets the combined front"
if grep -Fq '[mcp_servers.xcode]' "$REPO/.codex/config.toml"; then fail "Codex's direct bridge remains"; else pass "Codex's direct bridge is gone"; fi
assert_contains "$REPO/.codex/config.toml" '[mcp_servers.xcode-combined]' "Codex gets the combined front"
assert_contains "$REPO/.codex/config.toml" '[mcp_servers.other]' "Codex's unrelated entry survives"
assert_contains "$SB/claude-calls.txt" 'mcp add --scope project --transport http xcode-combined http://127.0.0.1:8767/mcp' "the Claude CLI receives the HTTP URL"

echo "== default bundle uninstall"
(
  cd "$REPO"
  PATH="$REPO/bin:$PATH" MAC_CONTROL_APP="$SB/MacControlMCP.app" MCP_TEST_CALLS="$SB/claude-calls.txt" "$ASTRA_ROOT/tools/mcp-bundle/setup-mcp.sh" --disable
) > "$SB/uninstall.out" 2>&1
assert_eq 0 "$?" "default uninstall succeeds"
assert_eq 'null' "$(jq -r '.mcpServers["xcode-combined"]' "$REPO/.mcp.json")" "Claude's combined entry is gone"
if [ -e "$REPO/.gemini/settings.json" ]; then fail "Gemini's combined-only config remains"; else pass "Gemini's combined-only config is gone"; fi
assert_contains "$REPO/.codex/config.toml" '[mcp_servers.other]' "Codex's unrelated entry survives uninstall"
finish
