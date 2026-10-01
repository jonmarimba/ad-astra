#!/usr/bin/env bash
# mcp-xcode-combined — point a repo at the ONE Xcode aggregator, over HTTP.
#
# The aggregator (tools/xcode-mcp-front, launchd job com.jonathansaggau.xcode-combined-front,
# port 8767) fronts Apple's mcpbridge AND Drew's server behind a single endpoint with a
# MEASURED sieve/map applied (tools/tool-templates/facts/), one canonical `build` tool, and
# ONE approved process identity. A repo that direct-spawns `xcrun mcpbridge` instead mints a
# fresh bridge PID per session, and Xcode wants a per-PID approval — under Xcode 27 the
# unanswered dialog even CRASHES the bridge (assertionFailure in MCPBridge.main(), crash
# logs 2026-08-26..09-01). This tool exists so no repo ever direct-spawns those two servers.
#
# Writes an HTTP server entry (no process spawned, nothing to approve per-repo):
#   Claude Code -> <repo>/.mcp.json               (server "xcode-combined", type http)
#   Codex CLI   -> <repo>/.codex/config.toml      (only if that file already exists;
#                                                  codex on this Mac carries the entry
#                                                  user-globally, added 2026-09-01)
#
# The mcp-bundle engine handles stdio spawns only, so this writes its own entries.
# Dependencies: jq (Claude entry), python3 (codex toml edit).
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
     '.mcpServers[$name] = {"type":"http","url":$url}' "$MCPJSON" > "$tmp" \
     || { echo "mcp-xcode-combined: FAIL — $MCPJSON is not valid JSON; fix it by hand." >&2; exit 65; }
  mv "$tmp" "$MCPJSON"
else
  jq -n --arg name "$NAME" --arg url "$URL" \
     '{"mcpServers": {($name): {"type":"http","url":$url}}}' > "$MCPJSON"
fi
echo "mcp-xcode-combined: wrote $NAME -> $URL into $MCPJSON"

# Codex keeps per-repo config in <repo>/.codex/config.toml. Only touch it if the repo
# already opted into one — codex on this machine has the aggregator user-globally.
CODEXTOML="$TARGET/.codex/config.toml"
if [ -f "$CODEXTOML" ]; then
  python3 - "$CODEXTOML" "$NAME" "$URL" <<'PY'
import sys
path, name, url = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
header = f"[mcp_servers.{name}]"
if header in s:
    print(f"mcp-xcode-combined: {path} already has {header}; left as-is")
else:
    with open(path, "a") as f:
        f.write(f"\n{header}\nurl = \"{url}\"\n")
    print(f"mcp-xcode-combined: appended {header} to {path}")
PY
fi

exit 0
