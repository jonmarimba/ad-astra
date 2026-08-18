#!/bin/bash
# MIXED-VERSION ROLLOUT — the real gate on adopting botline.
#
# GhOST-OpenClaw's attack item (1): "one side on the old syn/ack schema while the
# other writes syn/synack/ack — does either side false-alarm, corrupt, or
# permanently wedge?"
#
# This is not hypothetical. Both live agents currently run hand-written TWO-LEG
# implementations where `ack` means "the partner's syn, echoed". botline is
# THREE-leg: that echo lives in `synack`, and `ack` carries leg three. Same key
# names, different meanings — so a one-sided cutover is not a partial upgrade,
# it is two implementations confidently misreading each other.
#
# The requirement is NOT that a mixed pair works. It cannot work. The requirement
# is that it DEGRADES SAFELY: botline must notice the mismatch and say so, rather
# than silently concluding its partner is dead and texting a human at 3am.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$DIR"
TMP="$(mktemp -d)"

python3 - "$TMP/mixed.json" <<'PY'
import json, sys, uuid
from datetime import datetime, timezone
from botline import Botline

path = sys.argv[1]
fail = []
bl = Botline(path, me="ghost_claude", partner="openclaw")

def legacy_two_leg_run():
    """Faithful stand-in for the CURRENTLY DEPLOYED two-leg peer: mints a fresh
    syn every run, echoes the partner's syn into `ack`, never writes `synack`,
    and counts a miss whenever the partner's `ack` is not its own last syn."""
    try:
        s = json.load(open(path))
    except Exception:
        s = {}
    prev = s.get("openclaw", {})
    mine_prev_syn = prev.get("syn")
    theirs = s.get("ghost_claude", {})
    misses = prev.get("handshake_misses", 0)
    if mine_prev_syn and theirs.get("ack") != mine_prev_syn:
        misses += 1
    elif mine_prev_syn:
        misses = 0
    s["openclaw"] = {
        "last_check": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "status": "healthy",
        "problems": [],
        "syn": uuid.uuid4().hex[:12],
        "ack": theirs.get("syn"),          # two-leg meaning
        "handshake_misses": misses,
        "protocol": "two-leg/1",
    }
    json.dump(s, open(path, "w"), indent=2)
    return misses

# Ten alternating cycles of a mixed pair.
legacy_misses = 0
claude_alarmed_at = None
for i in range(10):
    r = bl.exchange(status="healthy")
    legacy_misses = legacy_two_leg_run()
    if r.should_alarm and claude_alarmed_at is None:
        claude_alarmed_at = i

final = bl.exchange(status="healthy")
mismatch_flagged = any("PROTOCOL MISMATCH" in c for c in final.counterpart)

# 1. The mismatch must be NAMED. Silence here is the dangerous outcome: it means
#    botline is misreading a live peer as an unresponsive one.
if not mismatch_flagged:
    fail.append("did not flag the protocol mismatch — would silently misread a live peer")

# 2. It must not claim the partner is DEAD. The peer is running perfectly; only
#    the schema disagrees. Reporting death here is the 3am text we are avoiding.
death_claims = [c for c in final.counterpart
                if "has not answered" in c or "absent" in c.lower()]
if death_claims:
    fail.append(f"claimed the partner was dead during a protocol mismatch — the "
                f"peer is running fine, only the schema disagrees: {death_claims[0][:80]}")
# And it must not ALARM at all on handshake grounds while the schema is known
# untrustworthy. Alarming off a handshake you have declared unreliable is
# incoherent, and in a mixed pair the partner is usually perfectly healthy.
if claude_alarmed_at is not None:
    fail.append(f"raised a handshake alarm at cycle {claude_alarmed_at} despite "
                f"having flagged the protocol as untrustworthy")
if final.should_alarm:
    fail.append("still in alarm state at the end of a mixed-version run")

# 3. Neither side may corrupt the file or lose the other's key.
s = json.load(open(path))
for k in ("ghost_claude", "openclaw"):
    if k not in s:
        fail.append(f"{k}'s key was lost during mixed-version operation")

# 4. It must not WEDGE: after both sides speak the same protocol again, a normal
#    handshake has to complete. This is what makes a rollback survivable.
s["openclaw"] = {
    "last_check": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "status": "healthy", "problems": [],
    "syn": "peer-syn-1",
    "synack": s["ghost_claude"]["syn"],     # now speaking three-leg
    "ack": None,
    "protocol": "botline/2",
}
json.dump(s, open(path, "w"), indent=2)
recovered = bl.exchange(status="healthy")
if not recovered.partner_answered:
    fail.append("did NOT recover after the peer upgraded — permanently wedged")

print("FAIL: " + "; ".join(fail) if fail else
      f"mixed-version: mismatch flagged, no false death claim, keys intact, "
      f"recovered after peer upgrade (legacy peer misses={legacy_misses}, "
      f"claude alarmed at cycle={claude_alarmed_at})")
sys.exit(1 if fail else 0)
PY
rc=$?
rm -rf "$TMP"
exit $rc
