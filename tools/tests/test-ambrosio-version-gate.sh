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

finish
