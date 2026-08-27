#!/usr/bin/env bash
# test-ambrosio-version-gate.sh — the redundancy check must not swallow a version jump.
#
# THE FAILURE THIS GUARDS. On 2026-08-26 ambrosio's trending scan found GLM-5.3-Flash and
# skipped it with "same family ('glm') already on the M5; not obviously new". The M5 held
# glm-4.7-flash. A two-major-version jump was suppressed and reported as routine, which is the
# same disease as the ollama watcher going silent: machinery deciding something is not new
# when it is.
#
# Every assertion runs the real gate against real strings. The RED controls prove the gate can
# still say "redundant" — a gate that always says "upgrade" would pass assertion 1 and be
# useless, because it would reinstate the dead-weight pulls the prefix check was added to stop.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
. ./lib.sh
GATE="$HOME/svnCheckouts/js-db-ad-astra/tools/ambrosio/version_gate.py"
[ -f "$GATE" ] || { fail "version_gate.py missing at $GATE"; finish; exit 1; }
need python3 "install python3"

M5="glm-4.7-flash
nemotron-3.5-lightning
qwen3.6-35b-a3b
gpt-oss-120b"

gate() { printf '%s\n' "$M5" | python3 "$GATE" "$1"; }

# 1. THE LIVE FAILURE. 5.3 over 4.7 must read as an upgrade.
out="$(gate 'GLM-5.3-Flash')"
case "$out" in
  upgrade*4.7*) pass "GLM-5.3 over glm-4.7 reads as an upgrade, naming what is held";;
  *) fail "GLM-5.3 did not read as an upgrade — got: $out";;
esac

# 2. RED CONTROL. The check the prefix heuristic was added for must still suppress.
#    Nemotron-3-Nano beside Nemotron-3.5-Lightning was dead weight, 2026-08-14.
out="$(gate 'Nemotron-3-Nano')"
case "$out" in
  redundant*) pass "RED control: older same-family model still suppressed";;
  *) fail "RED control failed — dead-weight model was not suppressed: $out";;
esac

# 3. RED CONTROL. The identical version must suppress too, or every run re-pulls.
out="$(gate 'glm-4.7')"
case "$out" in
  redundant*) pass "RED control: same version suppressed";;
  *) fail "RED control failed — same version not suppressed: $out";;
esac

# 4. A family absent from the host is simply new.
out="$(gate 'Mistral-Large-3')"
case "$out" in
  new) pass "unseen family reads as new";;
  *) fail "unseen family did not read as new — got: $out";;
esac

# 5. A SIZE SUFFIX IS NOT A VERSION. "35b" must not be read as version 35, which would make
#    every qwen candidate look ancient and suppress the whole family forever.
out="$(gate 'Qwen3.8-Flash-Next')"
case "$out" in
  upgrade*) pass "3.8 over 3.6 is an upgrade; the 35b size suffix is not read as a version";;
  *) fail "size suffix confused the comparison — got: $out";;
esac

# 6. MULTI-DIGIT COMPONENTS COMPARE NUMERICALLY, NOT AS TEXT.
#    String comparison puts "3.10" below "3.9" and would suppress a real release.
out="$(printf 'qwen3.9\n' | python3 "$GATE" 'Qwen3.10')"
case "$out" in
  upgrade*) pass "3.10 beats 3.9 (numeric, not lexical)";;
  *) fail "lexical version comparison — got: $out";;
esac

# 7. UNKNOWN NEVER SUPPRESSES. A host entry with no version must not be treated as newest.
out="$(printf 'glm-air\n' | python3 "$GATE" 'GLM-5.3-Flash')"
case "$out" in
  upgrade*) pass "unversioned host entry does not suppress a versioned candidate";;
  *) fail "unversioned host entry suppressed a candidate — got: $out";;
esac

# 8. A candidate with no version at all is surfaced rather than swallowed.
out="$(gate 'glm-air')"
case "$out" in
  upgrade*) pass "unversioned candidate is surfaced, not suppressed";;
  *) fail "unversioned candidate was suppressed — got: $out";;
esac

# ---------------------------------------------------------------------------
# AN OLD CONFIG FILE MUST NOT KILL A NEW SETTING.
# ambrosio writes its config once, on first run, and every later run just sources it. A setting
# added only to that heredoc is invisible to existing installations, and under `set -u` the
# first use aborts. TREND_LIMIT shipped that way on 2026-08-26: the 23:43 scheduled run died
# with "TREND_LIMIT: unbound variable" while ambrosio still exited 0 and reported healthy.
#
# This runs the real script against a config written the way an OLD installation's would be —
# the settings that existed before tonight, and nothing since. Checking behaviour rather than
# grepping for a pattern, because the pattern cannot tell a setting added last week from one
# that has always been there.
# ---------------------------------------------------------------------------
AMB="$HOME/svnCheckouts/js-db-ad-astra/tools/ambrosio/ambrosio"
OLDHOME="$SB/oldhome"; mkdir -p "$OLDHOME"
cat > "$OLDHOME/config" <<'CFG'
HOST="unreachable.invalid"
LMS_PORT="1234"
SSH_TARGET="unreachable.invalid"
WATCHLIST="glm kimi"
SIZE_CAP_GB="80"
OMNIROUTE_NODE="LM Studio M5"
LMS_BIN="/nonexistent/lms"
LMS_FORMAT="--mlx"
MAX_PER_RUN="2"
MIN_PARAMS_B="7"
CLOUD="1"
CFG
# CURL points at a stub so no assertion touches the network; the host is unreachable so the
# local half is a no-op. What is under test is only whether the script survives its own config.
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/bin-curl"; chmod +x "$SB/bin-curl" 2>/dev/null || { mkdir -p "$SB"; printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/bin-curl"; chmod +x "$SB/bin-curl"; }
out="$(AMBROSIO_HOME="$OLDHOME" CURL="$SB/bin-curl" BOTLINE_BIN=/nonexistent timeout 120 bash "$AMB" check --dry-run 2>&1)"
case "$out" in
  *"unbound variable"*) fail "a config predating tonight's settings aborts the run: $out";;
  *) pass "a config written before the newest settings does not abort the run";;
esac

# ---------------------------------------------------------------------------
# THE TRENDING WATCH MUST NOT REPORT A REQUANT OF A FAMILY WE ALREADY TRACK.
# Its first live run texted Jonathan at 03:47 about AtomicChat/Qwen3.8-Flash-Next-GGUF —
# a community repackage of a family already on the watchlist and already pulled. Hugging Face
# trending is full of those, and reporting them one line at a time is the laundry list he
# objected to. What he asked not to miss is a family we do not track at all.
#
# Checked against the tool's own reason string rather than by running the network: "new org"
# alone must not qualify; "off-watchlist" must.
# ---------------------------------------------------------------------------
AMB2="$HOME/svnCheckouts/js-db-ad-astra/tools/ambrosio/ambrosio"
gate_block="$(sed -n '/ONLY report a model whose FAMILY is unknown/,/esac/p' "$AMB2")"
case "$gate_block" in
  *"off-watchlist"*continue*) pass "trending watch reports only families off the watchlist";;
  *) fail "the family gate is missing from run_trending — a requant of a known family would be reported";;
esac

# A held overnight report must be DELIVERED later, not dropped. The model is marked told the
# moment it is seen, so a gate with no delivery path would silence it permanently.
case "$(sed -n '/Deliver anything the quiet-hours gate held/,/fi/p' "$AMB2")" in
  *BOTLINE*) pass "quiet-hours holds are delivered after the gate lifts, not dropped";;
  *) fail "held trending reports have no delivery path — the quiet gate is a silent drop";;
esac

# ---------------------------------------------------------------------------
# JUNK FILTERING MUST CATCH BOTH SPELLINGS OF THE JAILBROKEN VARIANTS.
# Within a minute of adding "ornith" to the watchlist on 2026-08-27, the trending watch texted
# Jonathan about OBLITERATUS/Ornith-1.5-9B-OBLITERATED. The filters listed "abliterated",
# which is the usual spelling, and that name uses the other one. These variants are exactly
# what the junk list exists to keep out of a channel he has already objected to as noisy.
# ---------------------------------------------------------------------------
AMB3="$HOME/svnCheckouts/js-db-ad-astra/tools/ambrosio/ambrosio"
missing_junk=""
for filt in $(grep -c "obliterat" "$AMB3"); do :; done
[ "$(grep -c "obliterat" "$AMB3")" -eq 3 ] \
  && pass "all three junk filters catch the OBLITERAT spelling, not just ABLITERAT" \
  || fail "only $(grep -c "obliterat" "$AMB3") of 3 junk filters catch the OBLITERAT spelling"

finish
