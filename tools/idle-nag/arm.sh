#!/bin/bash
# Stop hook: Claude finished a turn and is waiting on you. Arms a delayed spoken
# nag that fires only if you stay away. UserPromptSubmit (cancel.sh) disarms it;
# a later Stop re-arms with a new nonce so a stale waiter stays silent.
# Knobs (env): IDLE_NAG_DELAY seconds (25), IDLE_NAG_PHRASE, IDLE_NAG_SAY (say),
# IDLE_NAG_REQUIRE_DISPLAY (1 = speak only while the display is awake).
HERE="$(cd "$(dirname "$0")" && pwd)"
sid="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id") or "unknown")
except Exception: print("unknown")')"
dir="${TMPDIR:-/tmp}/astra-idle-nag"; mkdir -p "$dir"
export IDLE_MARKER="$dir/idle_$sid" IDLE_NONCE="$$-$(date +%s)"
echo "$IDLE_NONCE" > "$IDLE_MARKER"
nohup "$HERE/wait.sh" >/dev/null 2>&1 &
exit 0
