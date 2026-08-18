#!/bin/bash
# TRUE two-process contention for botline.
#
# GhOST-OpenClaw, reviewing the suite 2026-08-18: "current tests manually rewrite
# JSON without the flock; add true two-process contention/retry coverage." Correct
# — every other test in this directory writes the state file directly with
# open(path,"w"), which BYPASSES the very lock the module's safety rests on. Those
# tests could pass against an implementation with no locking at all.
#
# This spawns two real OS processes that hammer exchange() against one file and
# asserts the property that actually matters: neither agent's key is ever lost or
# corrupted, no matter how the writes interleave.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$DIR"
TMP="$(mktemp -d)"
STATE="$TMP/contend.json"

cat > "$TMP/worker.py" <<'PY'
import sys, time, random
from botline import Botline
path, me, partner, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
bl = Botline(path, me=me, partner=partner)
for i in range(n):
    bl.exchange(status="healthy", info=[f"{me} iter {i}"])
    time.sleep(random.uniform(0, 0.004))   # jitter to vary the interleaving
PY

python3 "$TMP/worker.py" "$STATE" alice bob 120 &
P1=$!
python3 "$TMP/worker.py" "$STATE" bob alice 120 &
P2=$!
wait $P1; R1=$?
wait $P2; R2=$?

python3 - "$STATE" "$R1" "$R2" <<'PY'
import json, sys
path, r1, r2 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
fail = []
if r1 or r2: fail.append(f"a worker crashed (exits {r1}/{r2})")
try:
    s = json.load(open(path))
except Exception as e:
    print(f"FAIL: state file is not valid JSON after contention: {e}"); sys.exit(1)

# THE property: concurrent read-modify-write must never drop the other agent's
# key. A lost update here means the flock is not actually protecting anything.
for k in ("alice", "bob"):
    if k not in s: fail.append(f"{k}'s key was LOST during contention")
    else:
        for f in ("syn", "handshake_misses", "last_check", "protocol"):
            if f not in s[k]: fail.append(f"{k} missing field {f}")

# Neither side should have alarmed: both ran constantly and answered constantly.
for k in ("alice", "bob"):
    m = s.get(k, {}).get("handshake_misses", 0)
    if m >= 3: fail.append(f"{k} reached alarm state ({m} misses) against a live partner")

print("FAIL: " + "; ".join(fail) if fail else
      f"contention: both keys intact after 240 concurrent exchanges "
      f"(alice misses={s['alice']['handshake_misses']}, "
      f"bob misses={s['bob']['handshake_misses']})")
sys.exit(1 if fail else 0)
PY
rc=$?
rm -rf "$TMP"
exit $rc
