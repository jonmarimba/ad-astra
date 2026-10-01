#!/usr/bin/env bash
# test-run-tiers.sh — the two-tier test runner, tested by effect in a sandbox.
#
# Increment 0.2 (tools/tool-templates/ROADMAP.md): run-all.sh is the fast tier and must
# (a) never execute a file marked '# TIER: slow' — the live-Xcode test launches Xcode and
# raises approval dialogs, so running it from the fast tier is not slowness, it is a GUI
# takeover — and (b) fail ITSELF when its wall time exceeds the budget, because a suite
# that quietly grows past fifteen seconds stops being run.
#
# The runners are copied into a sandbox with stub test files so this file can observe
# them without recursing (run-all runs this file; this file must not run the real
# run-all). Effects asserted: sentinel files the stubs create, the runners' own output
# and exit codes.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
need "$(basename "${TIMEOUT_BIN:-timeout}")" "brew install coreutils"

FAKE="$SB/tests"; mkdir -p "$FAKE" "$SB/lib"
cp "$HERE/run-all.sh" "$HERE/run-slow.sh" "$FAKE/"

cat > "$FAKE/test-fast-stub.sh" <<EOF
#!/usr/bin/env bash
touch "$SB/fast-ran"
echo "== test-fast-stub.sh: 1 ok, 0 failed"
EOF
cat > "$FAKE/test-slow-stub.sh" <<EOF
#!/usr/bin/env bash
# TIER: slow — stub for the tier test
touch "$SB/slow-ran"
echo "== test-slow-stub.sh: 1 ok, 0 failed"
EOF
# The lib-side template tests run-slow.sh must pick up (they sit outside the glob).
cat > "$SB/lib/test-templates.sh" <<EOF
#!/usr/bin/env bash
touch "$SB/lib-templates-ran"
EOF
cat > "$SB/lib/test-astra-update.sh" <<EOF
#!/usr/bin/env bash
touch "$SB/lib-update-ran"
EOF

# --- fast tier: runs the fast stub, does NOT run the slow-marked one ---
out="$SB/fast.out"
bash "$FAKE/run-all.sh" >"$out" 2>&1
assert_eq "0" "$?" "fast tier exits 0 when its files pass"
assert_file "$SB/fast-ran" "fast tier executed the unmarked file"
assert_no_file "$SB/slow-ran" "fast tier did NOT execute the '# TIER: slow' file"
assert_contains "$out" "skipped 1 slow-tier file" "fast tier says out loud what it skipped"

# --- a file that merely MENTIONS the marker (heredoc, assertion) is NOT slow ---
# This file itself was misclassified on 2026-08-31: its stub heredocs contain the marker
# at column 1, and a whole-file grep quietly dropped the tier test from the fast tier.
cat > "$FAKE/test-mentions-marker-stub.sh" <<'STUB'
#!/usr/bin/env bash
# a fast test whose BODY quotes the marker, far from the top
cat >/dev/null <<EOF
# TIER: slow — quoted content, not a classification
EOF
touch "${MENTION_SENTINEL:?}"
echo "== test-mentions-marker-stub.sh: 1 ok, 0 failed"
STUB
MENTION_SENTINEL="$SB/mention-ran" bash "$FAKE/run-all.sh" >/dev/null 2>&1
assert_file "$SB/mention-ran" "a file that only quotes the marker in its body still runs in the fast tier"
rm "$FAKE/test-mentions-marker-stub.sh"

# --- fast tier budget: total time over budget is a FAILURE, not a note ---
# PERFILE is raised above the file's own runtime so this tests the TOTAL-TIME budget
# specifically, not the per-file hang kill (which is a different failure, tested below).
# The sluggish file finishes; the tier's elapsed time exceeds the 1s budget.
cat > "$FAKE/test-sluggish-stub.sh" <<'EOF'
#!/usr/bin/env bash
sleep 2
echo "== test-sluggish-stub.sh: 1 ok, 0 failed"
EOF
red "fast tier over TOTAL budget must fail loudly" 1 "FAST TIER OVER BUDGET" \
  env ASTRA_FAST_BUDGET_S=1 ASTRA_FAST_PERFILE_S=10 bash "$FAKE/run-all.sh"
rm "$FAKE/test-sluggish-stub.sh"

# --- a HUNG test file is killed and fails; the tier does not stall forever ---
# The budget check ran only after every file exited, so one wedged file made the tier
# wait indefinitely and never report — the "budget is an assertion" claim could not
# catch the failure that actually stops the suite (adversarial round #3, executed with
# sleep 300). Per-file timeout now kills it.
cat > "$FAKE/test-hung-stub.sh" <<'EOF'
#!/usr/bin/env bash
sleep 300
EOF
# The whole run must itself finish well under the hang: an external timeout proves the
# tier did NOT block on the 300s sleep.
"$TIMEOUT_BIN" 40 env ASTRA_FAST_PERFILE_S=3 ASTRA_FAST_BUDGET_S=60 bash "$FAKE/run-all.sh" >"$SB/hung.out" 2>&1
rc=$?
assert_eq "1" "$rc" "the tier finished (not killed by the external 40s watchdog) and reported failure"
assert_contains "$SB/hung.out" "was KILLED after" "the hung file is named as killed, not left to stall"
rm "$FAKE/test-hung-stub.sh"

# --- fast tier refuses to report green having run nothing ---
mkdir -p "$SB/empty-tests"; cp "$HERE/run-all.sh" "$SB/empty-tests/"
cat > "$SB/empty-tests/test-only-slow.sh" <<'EOF'
#!/usr/bin/env bash
# TIER: slow — everything is slow here
EOF
red "fast tier with zero runnable files must fail" 1 "ran ZERO test files" \
  bash "$SB/empty-tests/run-all.sh"

# --- slow tier: runs ONLY the marked file, plus the lib-side template tests ---
rm -f "$SB/fast-ran"
out="$SB/slow.out"
bash "$FAKE/run-slow.sh" >"$out" 2>&1
assert_eq "0" "$?" "slow tier exits 0 when its files pass"
assert_file "$SB/slow-ran" "slow tier executed the '# TIER: slow' file"
assert_no_file "$SB/fast-ran" "slow tier did NOT execute the unmarked file"
assert_file "$SB/lib-templates-ran" "slow tier picked up lib/test-templates.sh (outside the glob)"
assert_file "$SB/lib-update-ran" "slow tier picked up lib/test-astra-update.sh (outside the glob)"

# --- the file whose fast-tier execution would take over the GUI stays marked ---
assert_contains "$HERE/test-xcode-mcp-front.sh" "# TIER: slow" \
  "the live-Xcode test carries the slow marker (fast tier must never launch Xcode)"

finish
