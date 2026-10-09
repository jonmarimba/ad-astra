#!/usr/bin/env bash
# TIER: slow — about 20 seconds of stub-server tests that start dozens of Python processes
# test-model-lab.sh — runs test_model_lab.py, the Python test suite for model-lab, and checks the launcher.
# The Python file is the real test and also runs on Windows; this wrapper puts it in astra's test tiers.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/../tests/lib.sh"
need python3 "brew install python"

out="$(python3 "$HERE/test_model_lab.py" 2>&1)"; rc=$?
echo "$out" | tail -n 4
assert_eq 0 "$rc" "test_model_lab.py passes"
ran="$(echo "$out" | sed -n 's/^Ran \([0-9]*\) tests.*/\1/p')"
[ "${ran:-0}" -ge 30 ] && pass "it ran $ran tests, so a silently empty run cannot pass" || fail "only ${ran:-0} tests ran; expected at least 30"

# the bash launcher runs the same program
export MODEL_LAB_HOME="$SB/home"
"$HERE/model-lab" profile set launcher-check --mem-gb 40 --bandwidth 250 > "$SB/launch.out" 2>&1
assert_eq 0 "$?" "the launcher runs model_lab.py"
assert_file "$SB/home/profiles/launcher-check.json" "and the profile landed in MODEL_LAB_HOME, not in the checkout"
"$HERE/model-lab" frobnicate > "$SB/bad.out" 2>&1
assert_eq 64 "$?" "RED: an unknown command exits 64 through the launcher"
ASTRA_PATH="$SB/empty" "$HERE/model-lab" --help > "$SB/nopy.out" 2>&1
assert_eq 69 "$?" "RED: with no Python on PATH the launcher says so and exits 69"
assert_contains "$SB/nopy.out" "needs Python 3.8" "RED: and names what is missing"
finish
