#!/bin/bash
# Regression coverage for literal Bash spellings of kill.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/no-killing-other-claudes.XXXXXX")"
victim=""
trap 'if [ -n "$victim" ]; then kill "$victim" 2>/dev/null || true; wait "$victim" 2>/dev/null || true; fi; rm -rf "$TMP_DIR"' EXIT
cp "$HERE/no-killing-other-claudes.sh" "$HERE/shell_word_literal.py" "$TMP_DIR/"
chmod +x "$TMP_DIR/no-killing-other-claudes.sh" "$TMP_DIR/shell_word_literal.py"

# The guard recognizes a live command line containing claude; this process is
# disposable and never receives the tested kill because the hook must block it.
bash -c 'exec -a "claude --resume disposable-guard-test" sleep 60' &
victim=$!
sleep 0.1

assert_blocked() {
  local command="$1"
  local label="$2"
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$command")"
  if printf '%s' "$payload" | "$TMP_DIR/no-killing-other-claudes.sh" >/dev/null 2>&1; then
    printf 'FAIL: %s was allowed\n' "$label"
    return 1
  fi
  if ! kill -0 "$victim" 2>/dev/null; then
    printf 'FAIL: %s killed the disposable process\n' "$label"
    return 1
  fi
  printf 'PASS: %s\n' "$label"
}

assert_blocked "k\$'\\151'll $victim" 'ANSI-C octal quote splice'
assert_blocked "\$'\\153\\151\\154\\154' $victim" 'fully ANSI-C quoted kill'
assert_blocked "k''ill $victim" 'ordinary quote splice'
assert_blocked "k\\ill $victim" 'backslash splice'
assert_blocked "\$verb $victim" 'variable-expanded command is unsupported'
assert_blocked "command \$verb $victim" 'wrapped variable-expanded command is unsupported'
continued=$'k\\\nill '
assert_blocked "${continued}${victim}" 'backslash-newline command spelling'
