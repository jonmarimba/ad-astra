#!/bin/bash
# repo-daemon-run.sh — launch THIS repo's autonomous MCP front daemon.
#
# Installed into <repo>/.astra/mcp-front/run.sh by repo-daemon-install.sh; everything is
# derived from its own location, so the same file works in every repo (portability
# doctrine: no hardcoded paths, no baked-in identity).
#
# PORT POLICY, per Jonathan's Phase 5 answer ("detect port collisions and fix them at
# launch"): the BASE port is deterministic from the repo path, so a repo keeps the same
# port across launches and .mcp.json stays put. At launch: first self-preempt any stale
# copy of OUR OWN daemon (matched by this exact daemon.py path — never anything else),
# then step past any FOREIGN listener one port at a time. A foreign listener is left
# alone; it is somebody's live service. The resolved port is written to ./port and into
# the repo's .mcp.json, which is how clients find the daemon.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"                 # <repo>/.astra/mcp-front
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

BASE_PORT=$(( 21000 + $(printf '%s' "$REPO_ROOT" | cksum | cut -d' ' -f1) % 3000 ))
if [ "${1:-}" = "--print-port" ]; then
  echo "$BASE_PORT"
  exit 0
fi

# Self-preempt: only a process running THIS repo's daemon.py. Matching the full path
# keeps this from ever touching another repo's daemon or an unrelated python.
for pid in $(pgrep -f "$HERE/daemon.py" 2>/dev/null); do
  [ "$pid" = "$$" ] && continue
  echo "repo-daemon: preempting stale daemon (pid $pid) for $REPO_ROOT"
  kill "$pid" 2>/dev/null || true
done
sleep 1

PORT=$BASE_PORT
while lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
  PORT=$((PORT + 1))
done
echo "$PORT" > "$HERE/port"

# Record the resolved endpoint where clients look. jq writes beside-and-rename so a
# crash mid-write cannot corrupt the repo's .mcp.json.
MCP_JSON="$REPO_ROOT/.mcp.json"
[ -f "$MCP_JSON" ] || printf '{"mcpServers": {}}\n' > "$MCP_JSON"
jq --arg url "http://127.0.0.1:$PORT/mcp" \
   '.mcpServers["astra-front"] = {"type": "http", "url": $url}' \
   "$MCP_JSON" > "$MCP_JSON.tmp" && mv "$MCP_JSON.tmp" "$MCP_JSON"

export XCODE_MCP_FRONT_MCP_INFO="$HERE/_mcp_info.json"
export XCODE_MCP_FRONT_PORT="$PORT"
export XCODE_MCP_FRONT_HOME="$HERE/home"
export XCODE_MCP_FRONT_SERVER_NAME="astra-front-$(basename "$REPO_ROOT")"
mkdir -p "$XCODE_MCP_FRONT_HOME"

exec uv run --script "$HERE/daemon.py"
