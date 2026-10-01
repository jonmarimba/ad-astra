#!/bin/bash
# repo-daemon-run.sh — launch THIS repo's autonomous MCP front daemon.
#
# Installed into <repo>/.astra/mcp-front/run.sh by repo-daemon-install.sh; everything is
# derived from its own location, so the same file works in every repo (portability
# doctrine: no hardcoded paths, no baked-in identity).
#
# PORT POLICY, per Jonathan's Phase 5 answer ("detect port collisions and fix them at
# launch"): the BASE port is deterministic from the repo path, so a repo keeps the same
# port across launches and .mcp.json stays put. At launch: validate the config BEFORE
# any side effect, self-preempt only the pid this launcher itself recorded (with a
# TERM-wait-KILL escalation — the daemon observably wedges in stdio teardown, which a
# single TERM plus one second does not cover), then step past any FOREIGN listener one
# port at a time. A foreign listener is left alone; it is somebody's live service. The
# resolved port is written to ./port and into the repo's .mcp.json, which is how
# clients find the daemon.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"                 # <repo>/.astra/mcp-front
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
CONFIG="$HERE/_mcp_info.json"

BASE_PORT=$(( 21000 + $(printf '%s' "$REPO_ROOT" | cksum | cut -d' ' -f1) % 3000 ))
if [ "${1:-}" = "--print-port" ]; then
  echo "$BASE_PORT"
  exit 0
fi

# VALIDATE BEFORE ANY SIDE EFFECT — with the DAEMON'S OWN LOADER, not a shape check.
# The adversarial round broke the jq version: a shape-valid config carrying a field the
# loader rejects (a stray 'url') cleared the gate, preempted the running healthy
# daemon, rewrote .mcp.json, and only THEN died — tearing down a working deployment
# (findings/adversarial-run-side-effects.sh). `resolve` is the lenient runtime
# contract: it warns on a missing why and still serves, and rejects exactly what the
# daemon itself would refuse to start on. Its warnings go to our stderr, so the log
# still shows what the authoring check would have said.
if ! XCODE_MCP_FRONT_MCP_INFO="$CONFIG" python3 "$HERE/mcp_config.py" resolve >/dev/null; then
  echo "repo-daemon: $CONFIG would not load — the daemon would die on it, so nothing is" >&2
  echo "  preempted and nothing is rewritten. Fix the template's config and relaunch." >&2
  exit 78
fi

# Self-preempt: ONLY the pid this launcher recorded, and only after confirming that
# process is really running this repo's daemon.py (literal match, ps not pgrep — a
# pgrep -f pattern is an unanchored REGEX over every process's argv, and the phase-5
# panel demonstrated it matching a bystander `tail -f` on the installed file).
PIDFILE="$HERE/pid"
if [ -f "$PIDFILE" ]; then
  oldpid="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$oldpid" ] && ps -o command= -p "$oldpid" 2>/dev/null | grep -qF "$HERE/daemon.py"; then
    echo "repo-daemon: preempting stale daemon (pid $oldpid) for $REPO_ROOT"
    kill "$oldpid" 2>/dev/null || true
    waited=0
    while kill -0 "$oldpid" 2>/dev/null && [ "$waited" -lt 5 ]; do sleep 1; waited=$((waited+1)); done
    if kill -0 "$oldpid" 2>/dev/null; then
      # The wedged-teardown state stall_watchdog documents: TERM cannot reach it.
      echo "repo-daemon: pid $oldpid ignored TERM for ${waited}s — escalating to KILL"
      kill -9 "$oldpid" 2>/dev/null || true
      sleep 1
    fi
  fi
fi

PORT=$BASE_PORT
while lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
  PORT=$((PORT + 1))
done
echo "$PORT" > "$HERE/port"

# Record the resolved endpoint where clients look. A jq failure here (a hand-edited
# .mcp.json with a stray comma) must kill the launch where launchd can see it — a
# daemon serving on a port .mcp.json does not name is a daemon nobody can find.
MCP_JSON="$REPO_ROOT/.mcp.json"
[ -f "$MCP_JSON" ] || printf '{"mcpServers": {}}\n' > "$MCP_JSON"
if ! jq --arg url "http://127.0.0.1:$PORT/mcp" \
     '.mcpServers["astra-front"] = {"type": "http", "url": $url}' \
     "$MCP_JSON" > "$MCP_JSON.tmp"; then
  rm -f "$MCP_JSON.tmp"
  echo "repo-daemon: could not rewrite $MCP_JSON (malformed JSON?) — refusing to serve" >&2
  echo "  an endpoint clients cannot find. Fix the file and relaunch." >&2
  exit 70
fi
mv "$MCP_JSON.tmp" "$MCP_JSON"

export XCODE_MCP_FRONT_MCP_INFO="$CONFIG"
export XCODE_MCP_FRONT_PORT="$PORT"
export XCODE_MCP_FRONT_HOME="$HERE/home"
export XCODE_MCP_FRONT_SERVER_NAME="astra-front-$(basename "$REPO_ROOT")"
# A spawn-per-connect upstream (uvx, npx) may need to DOWNLOAD on first launch, and a
# 15-second initialize window kills the install mid-download every cycle, forever —
# the 2026-08-31 drews incident (SYNTHESIS_phase1). Sixty seconds covers a cold
# install; override per-repo if a template knows better.
export XCODE_MCP_FRONT_CONNECT_TIMEOUT_S="${XCODE_MCP_FRONT_CONNECT_TIMEOUT_S:-60}"
mkdir -p "$XCODE_MCP_FRONT_HOME"

# $$ becomes the daemon's pid at exec; recorded first so the next launch can preempt
# exactly this process and nothing else.
echo "$$" > "$PIDFILE"
exec uv run --script "$HERE/daemon.py"
