#!/bin/bash
# test-codex-toml.sh — removing one MCP server must not delete the user's settings.
#
# setup-mcp.sh edits .codex/config.toml, a file the user also writes by hand.
# Its removal step matched from [mcp_servers.<name>] forward to the next
# [mcp_servers. header or end of file, which is only correct when MCP entries
# happen to be last and nothing is interleaved. A Codex review on 2026-08-18
# ran it against a config with [features] and [projects] sitting between two
# server blocks and got back an EMPTY FILE.
#
# The test drives the real script's own removal path, not a copy of the logic,
# because the boundary condition is the entire bug and a reimplementation in
# the test would just repeat whichever version I believed.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$HERE/setup-mcp.sh"
PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "MISSING DEPENDENCY: $1 — install it, do not skip"; exit 1; }
}
need python3

# Extract the removal function's embedded python from the shipped script and run
# it, so the test exercises what actually ships.
extract_remover() {
  python3 - "$SETUP" <<'PY'
import sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
start = src.index("disable_codex_block_one()")
body = src[start:]
a = body.index("<<'PY'") + len("<<'PY'")
b = body.index("\nPY\n", a)
print(body[a:b])
PY
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
extract_remover > "$WORK/remove.py"
if [ ! -s "$WORK/remove.py" ]; then
  echo "MISSING: could not extract the removal step from $SETUP — it was renamed or restructured"
  exit 1
fi

fixture() {
  mkdir -p "$WORK/.codex"
  cat > "$WORK/.codex/config.toml" <<'EOF'
[mcp_servers.xcode]
command = "xcrun"
args = ["mcpbridge"]

[features]
web_search = true

[projects."/precious"]
trust_level = "trusted"

[mcp_servers.mobile-mcp]
command = "npx"
EOF
}

echo "== 1. Removing a server must leave unrelated sections alone =="
fixture
python3 "$WORK/remove.py" xcode "$WORK/.codex/config.toml"
c="$WORK/.codex/config.toml"
grep -q '^\[features\]' "$c"            && ok "[features] survived"            || bad "[features] was deleted"
grep -q 'precious' "$c"                 && ok "[projects] survived"            || bad "[projects] was deleted — user settings destroyed"
grep -q 'mobile-mcp' "$c"               && ok "the other MCP server survived"  || bad "an unrelated MCP server was deleted"

echo "== 2. ...and must actually remove the one it was asked to =="
# The control. A remover that does nothing at all would pass every check above.
if grep -q 'xcrun' "$c"; then
  bad "xcode was not removed — the tool does not work"
else
  ok "xcode removed"
fi

echo "== 3. Removing the last server must not corrupt the rest =="
fixture
python3 "$WORK/remove.py" mobile-mcp "$WORK/.codex/config.toml"
grep -q 'xcrun' "$c"        && ok "the earlier server survived"   || bad "removing the LAST block ate an earlier one"
grep -q '^\[features\]' "$c" && ok "[features] still survived"     || bad "[features] deleted when removing the last block"

echo "== 4. Removing a server that is not there must change nothing =="
fixture
before="$(cat "$c")"
python3 "$WORK/remove.py" not-installed "$WORK/.codex/config.toml"
if [ "$before" = "$(cat "$c")" ]; then
  ok "absent server left the file byte-identical"
else
  bad "removing an absent server modified the config"
fi

echo "== 5. A config of nothing but that one server ends up empty, not broken =="
printf '[mcp_servers.xcode]\ncommand = "xcrun"\n' > "$c"
python3 "$WORK/remove.py" xcode "$WORK/.codex/config.toml"
if [ ! -s "$c" ]; then
  ok "file emptied cleanly"
else
  bad "left residue: $(cat "$c")"
fi

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
