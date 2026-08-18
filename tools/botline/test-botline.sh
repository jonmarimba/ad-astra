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

# THIRD-LEG PROPERTY (GhOST-OpenClaw review): round_complete must be FALSE
# until a side has had its own SYN/ACK confirmed, and TRUE thereafter. Testing
# only that it eventually goes true would pass a version that returns True
# unconditionally — so assert the "not early" half too. That half is the one
# that can actually catch a false positive.
import os
p2 = path + ".rc"
for f in (p2, p2.replace(".json", "") + ".lock"):
    if os.path.exists(f): os.unlink(f)
C = Botline(p2, me="alice", partner="bob")
D = Botline(p2, me="bob", partner="alice")
r1 = C.exchange()                      # A: SYN
if r1.round_complete: fail.append("round_complete true on the very first SYN")
r2 = D.exchange()                      # B: SYN/ACK + own SYN
if r2.round_complete: fail.append("round_complete true before any ACK exists")
r3 = C.exchange()                      # A: ACK (+ answers B's SYN)
if r3.round_complete: fail.append("round_complete true on A before B confirmed A's synack")
r4 = D.exchange()                      # B sees its SYN/ACK was ACK'd
if not r4.round_complete: fail.append("B never reached round_complete after a full three-leg exchange")
r5 = C.exchange()
if not r5.round_complete: fail.append("A never reached round_complete after the round closed")
for extra_round in range(2):
    if not D.exchange().round_complete: fail.append("round_complete regressed on B")
    if not C.exchange().round_complete: fail.append("round_complete regressed on A")

# Reserved fields may not be overridden by a caller.
try:
    C.exchange(extra={"syn": "hijacked"})
    fail.append("caller was allowed to override the reserved 'syn' field")
except ValueError:
    pass
try:
    C.exchange(extra={"my_own_key": 1})
except ValueError:
    fail.append("caller rejected for a NON-reserved key")

rm = None
for i in range(4):
    s = st(); s["bob"]["syn"] = f"dead{i:08d}"; s["bob"]["synack"] = None
    open(path, "w").write(json.dumps(s))
    rm = A.exchange()
if not rm.should_alarm: fail.append("never alarmed on an unresponsive partner")

print("FAIL: " + "; ".join(fail) if fail else "botline: all handshake tests pass")
sys.exit(1 if fail else 0)
PY
