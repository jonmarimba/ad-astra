#!/bin/bash
# Regression coverage for transparent wrappers around truncators.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/no-silent-truncation.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
cp "$HERE/no-silent-truncation.sh" "$TMP_DIR/no-silent-truncation.sh"
printf '%s\n' 'mailq' > "$TMP_DIR/no-silent-truncation.watchlist"

pass=0
fail=0
assert_blocked() {
  local command="$1"
  local label="$2"
  if printf '{"tool_input":{"command":"%s"}}' "$command" | "$TMP_DIR/no-silent-truncation.sh" >/dev/null 2>&1; then
    printf 'FAIL: %s\n' "$label"
    fail=$((fail + 1))
  else
    printf 'PASS: %s\n' "$label"
    pass=$((pass + 1))
  fi
}

assert_blocked 'mailq search urgent | command /usr/bin/head -10' 'command wrapper plus path-qualified head'
assert_blocked 'mailq search urgent | FOO=1 head -10' 'environment assignment prefix'
assert_blocked 'mailq search urgent | env FOO=1 /usr/bin/tail -10' 'env wrapper plus path-qualified tail'
assert_blocked 'mailq search urgent | command sed -n 1,10p' 'command wrapper plus sed range'

printf '%s checks: %s passed, %s failed\n' "$((pass + fail))" "$pass" "$fail"
[ "$fail" -eq 0 ]
