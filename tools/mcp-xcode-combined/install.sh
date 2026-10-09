#!/usr/bin/env bash
# astra-scope: repo-config
# mcp-xcode-combined — point a repo at the ONE Xcode aggregator, over HTTP.
#
# The aggregator (tools/xcode-mcp-front, launchd job <prefix>.xcode-combined-front,
# port 8767) fronts Apple's mcpbridge AND Drew's server behind a single endpoint with a
# MEASURED sieve/map applied (tools/tool-templates/facts/), one canonical `build` tool, and
# ONE approved process identity. A repo that direct-spawns `xcrun mcpbridge` instead mints a
# fresh bridge PID per session, and Xcode wants a per-PID approval — under Xcode 27 the
# unanswered dialog even CRASHES the bridge (assertionFailure in MCPBridge.main(), crash
# logs 2026-08-26..09-01). This tool exists so no repo ever direct-spawns those two servers.
#
# Writes an HTTP server entry for ALL THREE agents (no process spawned, nothing to approve per-repo):
#   Claude Code -> <repo>/.mcp.json               (server "xcode-combined", type http)
#   Qwen Code   -> <repo>/.qwen/settings.json     (mcpServers.xcode-combined.httpUrl)
#   Codex CLI   -> <repo>/.codex/config.toml      ([mcp_servers.xcode-combined] url)
# Each file is created when it is missing. That matters: Qwen and Codex take a project config INSTEAD
# of the user-level one, not merged with it, so a repo whose other MCP servers made a project config
# but whose Xcode entry did not would lose Xcode in that agent. This tool used to write the Codex
# entry only if .codex/config.toml already existed and never wrote Qwen's, so the first install of
# swift-ios (this tool runs before the bundle creates those files) left Codex without Xcode until a
# second install, and Qwen without it for good (found 2026-10-08 by test-template-swift.sh).
#
# The mcp-bundle engine handles stdio spawns only, so this writes its own entries.
# Dependencies: jq (Claude and Qwen entries), python3 (codex toml edit).
#
# Usage: ./install.sh --into <repo>
set -uo pipefail

URL="${XCODE_COMBINED_URL:-http://127.0.0.1:8767/mcp}"
NAME="xcode-combined"

TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="${2:-}"; shift 2 ;;
    *) echo "mcp-xcode-combined: unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "mcp-xcode-combined: no such directory: $TARGET" >&2; exit 66; }
command -v jq >/dev/null || { echo "mcp-xcode-combined: FAIL — jq missing. brew install jq" >&2; exit 69; }

MCPJSON="$TARGET/.mcp.json"
if [ -f "$MCPJSON" ]; then
  tmp="$(mktemp)"
  jq --arg name "$NAME" --arg url "$URL" \
     'del(.mcpServers.xcode, .mcpServers."xcode-mcp-server", .mcpServers.XcodeBuildMCP, .mcpServers."xcode-mcp-front") | .mcpServers[$name] = {"type":"http","url":$url}' "$MCPJSON" > "$tmp" \
     || { echo "mcp-xcode-combined: FAIL — $MCPJSON is not valid JSON; fix it by hand." >&2; exit 65; }
  mv "$tmp" "$MCPJSON"
else
  jq -n --arg name "$NAME" --arg url "$URL" \
     '{"mcpServers": {($name): {"type":"http","url":$url}}}' > "$MCPJSON"
fi
echo "mcp-xcode-combined: wrote $NAME -> $URL into $MCPJSON"

# Qwen keeps per-repo config in <repo>/.qwen/settings.json; an HTTP server is a `httpUrl` entry (the
# shape `qwen mcp add --scope project --transport http` writes).
QWENJSON="$TARGET/.qwen/settings.json"
mkdir -p "$TARGET/.qwen"
if [ -f "$QWENJSON" ]; then
  tmp="$(mktemp)"
  jq --arg name "$NAME" --arg url "$URL" 'del(.mcpServers.xcode, .mcpServers."xcode-mcp-server", .mcpServers.XcodeBuildMCP, .mcpServers."xcode-mcp-front") | .mcpServers[$name] = {"httpUrl":$url}' "$QWENJSON" > "$tmp" \
     || { rm -f "$tmp"; echo "mcp-xcode-combined: FAIL — $QWENJSON is not valid JSON; fix it by hand." >&2; exit 65; }
  mv "$tmp" "$QWENJSON"
else
  jq -n --arg name "$NAME" --arg url "$URL" '{"mcpServers": {($name): {"httpUrl":$url}}}' > "$QWENJSON"
fi
echo "mcp-xcode-combined: wrote $NAME -> $URL into $QWENJSON"

# Codex keeps per-repo config in <repo>/.codex/config.toml.
CODEXTOML="$TARGET/.codex/config.toml"
mkdir -p "$TARGET/.codex"
python3 - "$CODEXTOML" "$NAME" "$URL" <<'PY'
import os, sys
path, name, url = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read() if os.path.exists(path) else ""
legacy = {"[mcp_servers.xcode]", "[mcp_servers.xcode-mcp-server]", "[mcp_servers.XcodeBuildMCP]", "[mcp_servers.xcode-mcp-front]"}
kept, skip = [], False
for line in s.splitlines(keepends=True):
    if line.strip().startswith("["):
        table = line.strip()
        skip = table in legacy or any(table.startswith(prefix[:-1] + ".") for prefix in legacy)
    if not skip:
        kept.append(line)
s = "".join(kept)
header = f"[mcp_servers.{name}]"
if header in s:
    # Update the url inside OUR table only, so a changed XCODE_COMBINED_URL moves Codex with
    # the other two agents. Other tables, and every other line of our own table, stay as they are.
    lines, in_ours, done = s.split("\n"), False, False
    for i, line in enumerate(lines):
        if line.strip().startswith("["):
            in_ours = line.strip() == header
        elif in_ours and not done and line.strip().startswith("url"):
            lines[i] = f'url = "{url}"'
            done = True
    if not done:
        at = lines.index(header) + 1
        lines.insert(at, f'url = "{url}"')
    with open(path, "w") as f:
        f.write("\n".join(lines))
    print(f"mcp-xcode-combined: set url in {header} of {path}")
else:
    with open(path, "a") as f:
        f.write(("\n" if s and not s.endswith("\n\n") else "") + f"{header}\nurl = \"{url}\"\n")
    print(f"mcp-xcode-combined: wrote {header} into {path}")
PY

exit 0
