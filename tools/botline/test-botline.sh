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
import json, sys, os
from datetime import datetime, timezone, timedelta
path = sys.argv[1]
A = Botline(path, me="alice", partner="bob")
B = Botline(path, me="bob", partner="alice")
def st(): return json.load(open(path))
fail = []

seen = []
for _ in range(5):
    r = A.exchange()
    seen.append(st()["alice"]["syn_v2"])
    if r.should_alarm: fail.append("alarmed while partner had not run")
if len(set(seen)) != 1: fail.append(f"syn not held (changed {len(set(seen))}x)")

B.exchange()
if st()["bob"]["synack_v2"] != seen[0]: fail.append("partner answered a stale syn")
r = A.exchange()
if not r.partner_answered: fail.append("did not register the answer")
if st()["alice"]["syn_v2"] == seen[0]: fail.append("syn not advanced after answer")

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
    s = st(); s["bob"]["syn_v2"] = f"dead{i:08d}"; s["bob"]["synack_v2"] = None
    open(path, "w").write(json.dumps(s))
    rm = A.exchange()
if not rm.should_alarm: fail.append("never alarmed on an unresponsive partner")

# ── SILENT PARTNER: the dominant real-world death mode ────────────────────
# Convocation, 2026-08-18: the suite certified an implementation that could not
# detect a dead partner AT ANY HORIZON, because every alarm test hand-advanced
# the partner's syn — forging `partner_advanced`, the sole input to the miss
# counter. That tests the alive-but-rude case only. A partner whose process
# STOPS leaves its syn frozen forever, which the miss counter structurally
# cannot see. This test fails against that implementation, which is the point.
import time as _t
p3 = path + "-silent.json"
for f in (p3, p3.replace(".json", ".lock")):
    if os.path.exists(f): os.unlink(f)
E = Botline(p3, me="alice", partner="bob", silence_minutes=60)
F = Botline(p3, me="bob", partner="alice", silence_minutes=60)
E.exchange(); F.exchange(); E.exchange()      # a clean, completed round first

# Bob now simply stops running. Nothing is forged: its key is left exactly as
# its last real run left it, only the clock moves on.
s3 = st3 = json.load(open(p3))
old_ts = (datetime.now(timezone.utc) - timedelta(minutes=200)).isoformat(timespec="seconds")
s3["bob"]["protocol"] = "botline/2"
s3["bob"]["last_check"] = old_ts
open(p3, "w").write(json.dumps(s3))

r_sil = E.exchange()
if not r_sil.partner_absent:
    fail.append("did not detect a partner that stopped running (frozen syn, stale last_check)")
if not r_sil.should_alarm:
    fail.append("silent partner did not raise should_alarm")

# And the inverse: a partner that is merely SLOW must not read as absent.
s3 = json.load(open(p3))
s3["bob"]["last_check"] = (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat(timespec="seconds")
open(p3, "w").write(json.dumps(s3))
r_slow = E.exchange()
if r_slow.partner_absent:
    fail.append("a partner idle only 5m was wrongly reported absent")

# ── PROTOCOL MISMATCH must be refused, not silently misread ───────────────
p4 = path + "-proto.json"
for f in (p4, p4.replace(".json", ".lock")):
    if os.path.exists(f): os.unlink(f)
G = Botline(p4, me="alice", partner="bob")
G.exchange()
s4 = json.load(open(p4))
s4["bob"] = {"protocol": "two-leg/1", "syn_v2": "abc123",
             "last_check": datetime.now(timezone.utc).isoformat(timespec="seconds")}
open(p4, "w").write(json.dumps(s4))
r_proto = G.exchange()
if not any("PROTOCOL MISMATCH" in c for c in r_proto.counterpart):
    fail.append("did not flag a peer speaking an incompatible protocol version")

print("FAIL: " + "; ".join(fail) if fail else "botline: all handshake tests pass")
sys.exit(1 if fail else 0)
PY
