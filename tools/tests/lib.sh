#!/usr/bin/env bash
# lib.sh — shared assertions for the @astra tool tests. Source from every test-*.sh.
#
# The rules these tests follow are Jonathan's own (js-llmKicker/docs/TAUTOLOGY-AUDIT-20260801.md,
# docs/planning/07d-test-truthfulness/SPEC.md, AGENTS.md "a test that goes red is worth more than
# a paragraph that is true"):
#   1. Assert BY EFFECT — a file that exists, a message that routed, an exit code — never "it ran".
#   2. Every test file carries at least one RED control: an input that MUST fail. If the RED
#      control passes, the test is a tautology and the run fails.
#   3. No silent skips. A missing dependency is a loud FAIL with the reason, never a quiet pass.
#   4. Names don't overclaim: a test named for a fragment tests that fragment.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

TESTS_PASS=0; TESTS_FAIL=0
SB="$(mktemp -d -t astra-test)"          # per-test sandbox, wiped on exit
_lib_cleanup(){ rm -rf "$SB"; }
trap _lib_cleanup EXIT

pass(){ TESTS_PASS=$((TESTS_PASS+1)); echo "  ok:   $*"; }
fail(){ TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL: $*" >&2; }

need(){ # loud dependency gate — rule 3. usage: need <cmd> "<how to get it>"
  command -v "$1" >/dev/null && return 0
  fail "missing dependency '$1' ($2) — this is a FAILURE, not a skip"
  finish; exit 1
}

assert_eq(){        [ "$1" = "$2" ]        && pass "$3" || fail "$3 (want '$1' got '$2')"; }
assert_file(){      [ -f "$1" ]            && pass "$2" || fail "$2 (missing $1)"; }
assert_no_file(){   [ ! -e "$1" ]          && pass "$2" || fail "$2 (unexpected $1)"; }
assert_dir(){       [ -d "$1" ]            && pass "$2" || fail "$2 (missing dir $1)"; }
assert_contains(){ # an empty needle is a tautology — grep -F "" matches any nonempty file, so an
  # accidentally-unset variable (e.g. an unquoted ${x:-} that resolved to "") would green-light
  # against ANY real output instead of the specific string the caller meant to check for. Found
  # by convocation review (claude leg), 2026-08-14.
  [ -n "$2" ] || { fail "$3 (empty needle passed to assert_contains — tautology guard, fix the caller)"; return; }
  grep -qF -- "$2" "$1" 2>/dev/null && pass "$3" || fail "$3 ('$2' not in $1)"
}
assert_not_contains(){ # fails on a MISSING file too — "not present" must mean "checked and absent"
  [ -f "$1" ] || { fail "$3 (file $1 missing — vacuous pass refused)"; return; }
  grep -qF -- "$2" "$1" && fail "$3 ('$2' unexpectedly in $1)" || pass "$3"
}
assert_empty(){     [ -z "$1" ]            && pass "$2" || fail "$2 (expected empty, got '$1')"; }
assert_nonempty(){  [ -n "$1" ]            && pass "$2" || fail "$2 (expected output, got none)"; }

assert_rc(){ # usage: assert_rc <want-rc> "<label>" cmd args...
  local want="$1" label="$2"; shift 2
  "$@" >"$SB/.rc.out" 2>"$SB/.rc.err"; local got=$?
  [ "$got" = "$want" ] && pass "$label (rc=$got)" || { fail "$label (want rc=$want got rc=$got)"; sed 's/^/        /' "$SB/.rc.err" >&2; }
}

red(){ # RED control — rule 2. The command MUST fail (nonzero rc), and fail FOR THE RIGHT REASON —
  # not because the shell couldn't even find/run it. 126 (found, not executable) and 127 (command
  # not found) mean a typo'd path or missing binary, not the code under test rejecting bad input;
  # counting those as a passed RED control would let a broken invocation register as "tautology
  # guard confirmed" without ever exercising the real code. Found by convocation review (claude
  # leg), 2026-08-14. usage: red "<label>" cmd args...
  local label="$1"; shift
  "$@" >/dev/null 2>&1; local rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "RED control DID NOT FAIL (tautology): $label"
  elif [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
    fail "RED control failed for the WRONG reason (rc=$rc, command not found/executable — fix the invocation, this proves nothing): $label"
  else
    pass "red: $label"
  fi
}

finish(){
  # A test file that reaches finish() having run zero assertions (every assert sat behind a
  # conditional that never fired, an early return skipped them all, etc.) would otherwise print
  # "0 ok, 0 failed" and exit 0 — a silent-pass gate baked into the harness itself, worse than any
  # single tautological assertion because it hides EVERY test in the file at once. Found by
  # convocation review (claude + codex, independently), 2026-08-14.
  if [ "$((TESTS_PASS + TESTS_FAIL))" -eq 0 ]; then
    echo "== $(basename "$0"): ran ZERO assertions — this is a failure, not a silent pass" >&2
    return 1
  fi
  echo "== $(basename "$0"): $TESTS_PASS ok, $TESTS_FAIL failed"
  [ "$TESTS_FAIL" -eq 0 ]
}
