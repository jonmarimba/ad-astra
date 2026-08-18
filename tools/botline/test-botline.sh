#!/bin/bash
# RED-capable tests for botline's three-way handshake.
#
# The case that matters most is FAST-A/SLOW-B: one side polling faster than the
# other must never alarm, and its SYN must stay answerable. The first draft
# failed both and an earlier version of THIS FILE reported PASS anyway, because
# it compared the partner's synack against the LATEST syn — which matches
# trivially when the syn is being reminted every run. A test that restates the
# implementation instead of the property is worse than no test.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$DIR"
command -v python3 >/dev/null || { echo "MISSING DEPENDENCY: python3"; exit 1; }
STATE="$(mktemp -d)/hs.json"
python3 - "$STATE" <<'PY'
from botline import Botline
import json, sys
path = sys.argv[1]
A = Botline(path, me="alice", partner="bob")
B = Botline(path, me="bob", partner="alice")
def st(): return json.load(open(path))
fail = []

seen = []
for _ in range(5):
    r = A.exchange()
    seen.append(st()["alice"]["syn"])
    if r.should_alarm: fail.append("alarmed while partner had not run")
if len(set(seen)) != 1: fail.append(f"syn not held (changed {len(set(seen))}x)")

B.exchange()
if st()["bob"]["synack"] != seen[0]: fail.append("partner answered a stale syn")
r = A.exchange()
if not r.partner_answered: fail.append("did not register the answer")
if st()["alice"]["syn"] == seen[0]: fail.append("syn not advanced after answer")

rm = None
for i in range(4):
    s = st(); s["bob"]["syn"] = f"dead{i:08d}"; s["bob"]["synack"] = None
    open(path, "w").write(json.dumps(s))
    rm = A.exchange()
if not rm.should_alarm: fail.append("never alarmed on an unresponsive partner")

print("FAIL: " + "; ".join(fail) if fail else "botline: all handshake tests pass")
sys.exit(1 if fail else 0)
PY
