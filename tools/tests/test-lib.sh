#!/usr/bin/env bash
# test-lib.sh — the test harness's own RED-control helper, tested by effect.
#
# red() is the mechanism every other test file leans on to prove it can fail. Increment 0.1
# (tools/tool-templates/ROADMAP.md): the old red() discarded all output and accepted almost any
# nonzero exit, so a control "passed" when the command failed for a missing file or a typo'd
# flag — proving something broke, not that the guard rejected bad input. The new contract:
#
#   red "<label>" <want-rc> "<expected-diagnostic>" cmd args...
#
# passes ONLY when the command exits with exactly <want-rc> AND its combined stdout+stderr
# contains the literal <expected-diagnostic>.
#
# Each case here runs red in a CHILD bash that sources lib.sh fresh, so the child's pass/fail
# counters and finish() verdict are the observed effect, and this file's own counters stay
# clean. Asserted by effect: the child's printed verdict lines and its exit code.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

run_red(){ # usage: run_red <outfile-basename> red-arg... ; captures child output + exit code
  local out="$SB/$1"; shift
  bash -c '. "$1"; shift; red "$@"; finish' _ "$HERE/lib.sh" "$@" >"$out" 2>&1
  echo $? >"$out.rc"
}

# 1. A correct RED control: command fails with the declared rc and prints the declared
#    diagnostic. This is the only case that may pass.
run_red good "rejects url field" 64 "unimplemented field: url" \
  bash -c 'echo "config error — unimplemented field: url" >&2; exit 64'
assert_contains "$SB/good" "red: rejects url field" "red passes when rc and diagnostic both match"
assert_eq "0" "$(cat "$SB/good.rc")" "matching RED control leaves the child suite green"

# 2. Wrong exit code: the command failed, but not the way the caller declared. The old red()
#    passed this — that pass is exactly the defect 0.1 exists to remove.
run_red wrongrc "rejects url field" 64 "unimplemented field: url" \
  bash -c 'echo "no such file or directory" >&2; exit 1'
assert_contains "$SB/wrongrc" "FAIL" "red fails when the command dies with the wrong exit code"
assert_contains "$SB/wrongrc" "rc=1" "the wrong-rc failure names the rc it actually got"
assert_eq "1" "$(cat "$SB/wrongrc.rc")" "wrong-rc RED control fails the child suite"

# 3. Right rc, wrong words: exits as declared but never says the declared diagnostic, so
#    nothing shows the guard under test rejected the input for the claimed reason.
run_red wrongmsg "rejects url field" 64 "unimplemented field: url" \
  bash -c 'echo "segmentation fault" >&2; exit 64'
assert_contains "$SB/wrongmsg" "FAIL" "red fails when the expected diagnostic never appears"
assert_contains "$SB/wrongmsg" "unimplemented field: url" "the missing-diagnostic failure names what it looked for"
assert_eq "1" "$(cat "$SB/wrongmsg.rc")" "missing-diagnostic RED control fails the child suite"

# 4. The command succeeded: a RED control that does not fail is a tautology.
run_red tautology "rejects url field" 64 "unimplemented field: url" true
assert_contains "$SB/tautology" "DID NOT FAIL" "red fails loudly when the command succeeds"
assert_eq "1" "$(cat "$SB/tautology.rc")" "tautological RED control fails the child suite"

# 5. rc 127: the invocation itself is broken (command not found); proves nothing about the
#    code under test even if the caller asked for 127.
run_red notfound "rejects url field" 1 "anything" /no/such/binary-astra-test
assert_contains "$SB/notfound" "FAIL" "red fails when the command cannot even be found"
assert_eq "1" "$(cat "$SB/notfound.rc")" "command-not-found RED control fails the child suite"
run_red want127 "expects command-not-found" 127 "not found" /no/such/binary-astra-test
assert_contains "$SB/want127" "FAIL" "red refuses an expected rc of 127 — that is a broken invocation, not a guard"
assert_eq "1" "$(cat "$SB/want127.rc")" "expected-127 RED control fails the child suite"

# 6. An old-style call (no rc, no diagnostic) must fail loudly and name the migration,
#    never silently misparse its arguments as a command.
run_red oldstyle "old style call" false
assert_contains "$SB/oldstyle" "FAIL" "old-style red() call fails instead of misparsing"
assert_contains "$SB/oldstyle" "red label rc diagnostic cmd" "old-style failure states the new usage"
assert_eq "1" "$(cat "$SB/oldstyle.rc")" "old-style RED control fails the child suite"

# 7. An empty expected diagnostic is the same tautology assert_contains already refuses:
#    grep -F "" matches anything, so the check would green-light any failure output.
run_red emptymsg "empty diagnostic" 64 "" bash -c 'exit 64'
assert_contains "$SB/emptymsg" "FAIL" "red refuses an empty expected diagnostic"
assert_eq "1" "$(cat "$SB/emptymsg.rc")" "empty-diagnostic RED control fails the child suite"

finish
