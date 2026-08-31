#!/usr/bin/env bash
# test-mcp-tools.sh — mcp_tools.py's wire handling, against real stub servers.
#
# The defect all three round-one colloquium brands flagged: probe() assumed the NEXT
# stdout line answers the request just sent. A banner line before the handshake, or a
# spec-legal notification arriving between request and response, was misread as the
# answer or crashed the probe — the exact class of error the module's own docstring
# forbids. These tests speak to real child processes (stub_mcp_server.py) through the
# real CLI and assert on its stdout, stderr and exit codes.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need python3 "xcode-select --install"
MT="$HERE/../tool-templates/mcp_tools.py"
STUB="$HERE/stub_mcp_server.py"

cat > "$SB/cfg.json" <<EOF
{
  "mcpServers": {
    "plain":  {"command": "python3", "args": ["$STUB", "--name", "plain", "--tool", "ping=pong", "--tool", "build=ok"]},
    "chatty": {"command": "python3", "args": ["$STUB", "--name", "chatty", "--banner", "starting chatty v1...", "--notify-before-reply", "--tool", "ping=pong"]},
    "gated":  {"command": "python3", "args": ["$STUB", "--name", "gated", "--stall-tools", "--tool", "hidden=x"]}
  }
}
EOF

# --- a well-behaved server lists cleanly (the baseline the rest lean on) ---
python3 "$MT" list --config "$SB/cfg.json" --server plain >"$SB/plain.out" 2>&1
assert_eq "0" "$?" "a plain server lists with rc 0"
assert_contains "$SB/plain.out" "ping" "the tool names are listed"
assert_contains "$SB/plain.out" "plain 1.0-stub" "serverInfo name and version are reported"

# --- a banner line and interleaved notifications must not derail the probe ---
python3 "$MT" list --config "$SB/cfg.json" --server chatty >"$SB/chatty.out" 2>&1
assert_eq "0" "$?" "a server with a stdout banner and notifications still lists (rc 0)"
assert_contains "$SB/chatty.out" "ping" "the real tools/list answer is found past the chatter"
assert_not_contains "$SB/chatty.out" "Traceback" "no crash on non-JSON or notification lines"

# --- a server that never answers tools/list is a TIMEOUT, never an empty list ---
red "a gated server reads as a timeout naming the approval dialog, not as zero tools" 2 "approval dialog" \
  python3 "$MT" list --config "$SB/cfg.json" --server gated --timeout 3
python3 "$MT" list --config "$SB/cfg.json" --server gated --timeout 3 >"$SB/gated.out" 2>&1 || true
assert_not_contains "$SB/gated.out" "0 tools" "the gated server is never reported as having zero tools"

# --- compare refuses when one side failed to list ---
red "compare with an unlistable side refuses rather than reporting no collisions" 2 "Refusing to compare" \
  python3 "$MT" compare --config "$SB/cfg.json" --server plain --against gated --timeout 3

# --- compare finds the collision between two healthy servers ---
python3 "$MT" compare --config "$SB/cfg.json" --server plain --against chatty >"$SB/cmp.out" 2>&1
assert_eq "0" "$?" "compare of two healthy servers exits 0"
assert_contains "$SB/cmp.out" "EXACT NAME COLLISIONS: 1" "the shared 'ping' shows as an exact collision"

# --- no zombie children left behind ---
sleep 1
leftovers="$(pgrep -f "stub_mcp_server.py --name (plain|chatty|gated)" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$leftovers" "no stub child processes survive the probes"

finish
