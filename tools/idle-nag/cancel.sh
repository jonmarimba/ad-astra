#!/bin/bash
# UserPromptSubmit hook: you came back, so disarm this session's pending nag.
sid="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id") or "unknown")
except Exception: print("unknown")')"
rm -f "${TMPDIR:-/tmp}/astra-idle-nag/idle_$sid"
exit 0
