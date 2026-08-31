#!/usr/bin/env bash
# test-mcp-front-config.sh — the aggregator's config loader (tool-templates increment 1.1).
#
# The loader reads a Claude-Code-shaped _mcp_info.json — {"mcpServers": {name: {command,
# args}}} plus the wrapper's additive fields (prefix, quirks) — and REJECTS anything it
# would otherwise silently drop. The spec advertises the full Claude Code shape while the
# daemon passes only command and args to the child, so an ignored `env` or `url` is a
# late failure waiting for the first real call; rejection with the field's name is the
# contract. Exercised through the module's own CLI (validate <file>), asserting by effect
# on stdout, stderr and exit codes.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need python3 "xcode-select --install or brew install python3"
LOADER="$HERE/../xcode-mcp-front/mcp_config.py"
assert_file "$LOADER" "mcp_config.py exists next to the daemon"

ok_cfg="$SB/good.json"
cat > "$ok_cfg" <<'EOF'
{
  "mcpServers": {
    "xcode": {"command": "xcrun", "args": ["mcpbridge"], "quirks": ["require_xcode"]},
    "drews": {"command": "uvx", "args": ["drews-xcode-mcp"]}
  }
}
EOF

# --- the happy path: both upstreams parsed, prefixes defaulted from the server name ---
out="$SB/good.out"
python3 "$LOADER" validate "$ok_cfg" >"$out" 2>&1
assert_eq "0" "$?" "a valid two-upstream config validates"
assert_contains "$out" "xcode" "validate lists the first upstream"
assert_contains "$out" "drews" "validate lists the second upstream"
assert_contains "$out" "xcode__" "prefix defaults to the server name plus __"

# --- a command path containing a colon and an argument containing a comma survive ---
# Both are silently corrupted by the env-var format this file replaces (split(':') and
# split(',')); the JSON path must round-trip them intact.
tricky="$SB/tricky.json"
cat > "$tricky" <<'EOF'
{
  "mcpServers": {
    "odd": {"command": "/opt/we:ird/bin/serve", "args": ["--label", "a,b,c"]}
  }
}
EOF
out="$SB/tricky.out"
python3 "$LOADER" validate "$tricky" >"$out" 2>&1
assert_eq "0" "$?" "colon-in-command and comma-in-arg config validates"
assert_contains "$out" "/opt/we:ird/bin/serve" "a colon inside the command path survives parsing"
assert_contains "$out" "a,b,c" "a comma inside one argument stays one argument"

# --- unimplemented Claude Code fields are REJECTED BY NAME, never ignored ---
for field in env cwd url; do
  bad="$SB/has-$field.json"
  python3 - "$ok_cfg" "$bad" "$field" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
cfg["mcpServers"]["xcode"][sys.argv[3]] = {"A": "1"} if sys.argv[3] == "env" else "somewhere"
json.dump(cfg, open(sys.argv[2], "w"))
PY
  red "config with '$field' is rejected naming the field and the server" 65 "unimplemented field '$field' on server 'xcode'" \
    python3 "$LOADER" validate "$bad"
done

# --- the rest of the rejection surface, each with its own message ---
printf '{"mcpServers": {}}' > "$SB/empty.json"
red "empty mcpServers must fail" 65 "no non-empty mcpServers" \
  python3 "$LOADER" validate "$SB/empty.json"

printf '{"mcpServers": {"x": {"args": ["a"]}}}' > "$SB/nocmd.json"
red "server without a command must fail naming the server" 65 "server 'x' has no 'command'" \
  python3 "$LOADER" validate "$SB/nocmd.json"

printf '{"mcpServers": {"x": {"command": "c", "args": "not-a-list"}}}' > "$SB/badargs.json"
red "args that are not a list of strings must fail" 65 "server 'x': 'args' must be a list of strings" \
  python3 "$LOADER" validate "$SB/badargs.json"

printf '{"mcpServers": {"x": {"command": "c", "quirks": ["click_the_moon"]}}}' > "$SB/badquirk.json"
red "unknown quirk must fail naming it" 65 "unknown quirk 'click_the_moon' on server 'x'" \
  python3 "$LOADER" validate "$SB/badquirk.json"

printf '{"mcpServers": {"x": {"command": "c", "transporter": "beam"}}}' > "$SB/unknownkey.json"
red "an unrecognised key must fail, not be dropped" 65 "unknown field 'transporter' on server 'x'" \
  python3 "$LOADER" validate "$SB/unknownkey.json"

printf '{\n  // a jsonc comment\n  "mcpServers": {"x": {"command": "c"}}\n}' > "$SB/jsonc.json"
red "jsonc gets the point-at-the-generated-file message, not a bare parse error" 65 "not strict JSON" \
  python3 "$LOADER" validate "$SB/jsonc.json"

red "missing config file must fail as a missing file" 66 "cannot read" \
  python3 "$LOADER" validate "$SB/does-not-exist.json"

# --- resolve: how the daemon picks its upstreams (increment 1.2) ---
# The colon/comma env format is REPLACED, not deprecated: a set XCODE_MCP_FRONT_UPSTREAMS
# is a hard error pointing at the file, because the old parser silently corrupted a colon
# in a command path and a comma in an argument, and a daemon that half-honoured both
# mechanisms would hide which one won.
out="$SB/resolve-file.out"
env -u XCODE_MCP_FRONT_UPSTREAMS XCODE_MCP_FRONT_MCP_INFO="$ok_cfg" \
  python3 "$LOADER" resolve >"$out" 2>&1
assert_eq "0" "$?" "resolve honours XCODE_MCP_FRONT_MCP_INFO"
assert_contains "$out" "xcode__" "resolve keeps the xcode__ prefix from the file"
assert_contains "$out" "drews__" "resolve keeps the drews__ prefix from the file"

red "a set XCODE_MCP_FRONT_UPSTREAMS is refused, pointing at the file" 65 "replaced by _mcp_info.json" \
  env XCODE_MCP_FRONT_UPSTREAMS="xcode:1:xcrun:mcpbridge" python3 "$LOADER" resolve

red "UPSTREAMS set alongside the file is still refused — one mechanism must win visibly" 65 "replaced by _mcp_info.json" \
  env XCODE_MCP_FRONT_UPSTREAMS="x:1:c" XCODE_MCP_FRONT_MCP_INFO="$ok_cfg" python3 "$LOADER" resolve

# With neither set, the deployed single-upstream daemon's env contract is unchanged:
# default xcrun mcpbridge, Xcode required, served unprefixed.
out="$SB/resolve-single.out"
env -u XCODE_MCP_FRONT_UPSTREAMS -u XCODE_MCP_FRONT_MCP_INFO \
  python3 "$LOADER" resolve >"$out" 2>&1
assert_eq "0" "$?" "resolve with no env keeps the single-upstream default"
assert_contains "$out" "xcrun mcpbridge" "single-upstream default is still xcrun mcpbridge"
assert_contains "$out" "require_xcode" "single-upstream default still waits for Xcode"

out="$SB/resolve-drews.out"
env -u XCODE_MCP_FRONT_UPSTREAMS -u XCODE_MCP_FRONT_MCP_INFO \
  XCODE_MCP_FRONT_UPSTREAM_CMD=uvx XCODE_MCP_FRONT_UPSTREAM_ARGS=drews-xcode-mcp \
  XCODE_MCP_FRONT_REQUIRE_XCODE=0 python3 "$LOADER" resolve >"$out" 2>&1
assert_eq "0" "$?" "single-upstream env overrides still resolve"
assert_contains "$out" "uvx drews-xcode-mcp" "single-upstream CMD/ARGS overrides survive"
assert_not_contains "$out" "require_xcode" "REQUIRE_XCODE=0 drops the quirk"

finish
