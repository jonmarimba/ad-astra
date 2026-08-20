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
    # A strictly increasing per-agent sequence number. THIS is what makes a
    # lost update detectable: without the lock, a stale read-modify-write can
    # put an OLDER value back, so the sequence goes BACKWARDS. Merely checking
    # that both keys still exist cannot see that — an earlier version of this
    # test did exactly that and passed with flock disabled.
    bl.exchange(status="healthy", extra={"seq": i})
    time.sleep(random.uniform(0, 0.004))
PY

# A third process watches the file throughout and reports any REGRESSION in
# either side's sequence number — the direct signature of a lost update.
cat > "$TMP/monitor.py" <<'PY'
import json, sys, time
path, secs = sys.argv[1], float(sys.argv[2])
high = {}
regressions = []
end = time.time() + secs
while time.time() < end:
    try:
        s = json.load(open(path))
    except Exception:
        time.sleep(0.002); continue      # mid-replace or absent; not a finding
    for k, v in s.items():
        q = v.get("seq")
        if q is None: continue
        if k in high and q < high[k]:
            regressions.append(f"{k} seq went {high[k]} -> {q}")
        high[k] = max(high.get(k, q), q)
    time.sleep(0.002)
print(json.dumps(regressions))
PY

python3 "$TMP/monitor.py" "$STATE" 12 > "$TMP/mon.out" &
PM=$!
python3 "$TMP/worker.py" "$STATE" alice bob 120 &
P1=$!
python3 "$TMP/worker.py" "$STATE" bob alice 120 &
P2=$!
wait $P1; R1=$?
wait $P2; R2=$?
wait $PM

python3 - "$STATE" "$R1" "$R2" "$TMP/mon.out" <<'PY'
import json, sys
path, r1, r2, monf = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
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

# THE lock property: no lost updates. Without flock, a stale read-modify-write
# replaces a newer value with an older one and a sequence number goes backwards.
try:
    regressions = json.load(open(monf))
except Exception as e:
    regressions = []; fail.append(f"monitor produced no usable output: {e}")
if regressions:
    fail.append(f"LOST UPDATES — {len(regressions)} sequence regression(s): "
                + "; ".join(regressions[:3]))

print("FAIL: " + "; ".join(fail) if fail else
      f"contention: 240 concurrent exchanges, no lost updates, both keys intact "
      f"(alice misses={s['alice']['handshake_misses']}, "
      f"bob misses={s['bob']['handshake_misses']})")
sys.exit(1 if fail else 0)
PY
rc=$?
rm -rf "$TMP"
exit $rc
