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
# (env graduated to implemented in the Phase 1 hardening and has its own tests below)
for field in cwd url; do
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

# --- env is implemented, not rejected (Phase 1 hardening, claude-leg finding 9) ---
# The daemon's own docstring names XCODEMCP_ALLOWED_FOLDERS as Drew's auth mechanism,
# and the SDK's default child environment is a six-variable allowlist, so with env
# rejected there was NO way to configure it at all.
envcfg="$SB/envcfg.json"
cat > "$envcfg" <<'EOF'
{"mcpServers": {"withenv": {"command": "c", "env": {"ASTRA_TEST_VAL": "sekrit"}}}}
EOF
out="$SB/envcfg.out"
python3 "$LOADER" validate "$envcfg" >"$out" 2>&1
assert_eq "0" "$?" "a server with an env map validates"
assert_contains "$out" "ASTRA_TEST_VAL" "the env keys are shown in the validation listing"

printf '{"mcpServers": {"x": {"command": "c", "env": {"A": 1}}}}' > "$SB/badenv.json"
red "env values that are not strings are rejected" 65 "'env' must be an object of string values" \
  python3 "$LOADER" validate "$SB/badenv.json"

# --- unknown TOP-LEVEL keys are rejected too (all three phase-1 panel brands) ---
# Phase 2's sieve and Phase 3's map land at top level; a typo'd stanza that validates
# silently is a limiting policy that never applies.
printf '{"mcpServers": {"x": {"command": "c"}}, "denyLisp": []}' > "$SB/topkey.json"
red "an unknown top-level key is rejected by name" 65 "unknown top-level field 'denyLisp'" \
  python3 "$LOADER" validate "$SB/topkey.json"

# --- the prefix set must compose into an unambiguous surface (increment 1.3) ---
# Two upstreams sharing a prefix would collide exposed names; a prefix that is a prefix
# of another ('a__' and 'a__b__') makes routing 'a__b__tool' order-dependent. Both are
# config mistakes and both are rejected at load, when the author can still fix them —
# not at call time, when they surface as a misroute.
printf '{"mcpServers": {"one": {"command": "c", "prefix": "x__"}, "two": {"command": "c", "prefix": "x__"}}}' > "$SB/dup-prefix.json"
red "two upstreams with the same prefix are rejected" 65 "same prefix 'x__'" \
  python3 "$LOADER" validate "$SB/dup-prefix.json"

printf '{"mcpServers": {"a": {"command": "c"}, "abi": {"command": "c", "prefix": "a__b__"}}}' > "$SB/nested-prefix.json"
red "a prefix that is a prefix of another is rejected as order-dependent" 65 "prefix of" \
  python3 "$LOADER" validate "$SB/nested-prefix.json"

printf '{"mcpServers": {"a": {"command": "c", "prefix": ""}, "b": {"command": "c"}}}' > "$SB/empty-prefix.json"
red "an empty prefix beside another upstream is rejected (bare names would be unroutable)" 65 "empty prefix" \
  python3 "$LOADER" validate "$SB/empty-prefix.json"

# --- the sieve: per-server block lists (Phase 2; deny-list only, per Jonathan) ---
blockcfg="$SB/blockcfg.json"
cat > "$blockcfg" <<'EOF'
{"mcpServers": {"x": {"command": "c", "block": [
  {"tool": "SwitchScheme", "why": "scheme switching is owned by drews per the 2026-08-31 decision"}
]}}}
EOF
out="$SB/blockcfg.out"
python3 "$LOADER" validate "$blockcfg" >"$out" 2>&1
assert_eq "0" "$?" "a block entry with tool and why validates"
assert_contains "$out" "SwitchScheme" "the blocked tool is shown in the validation listing"

# why is DATA and it is REQUIRED at authoring time: a jsonc comment cannot be enforced,
# and a block without a stated cause is the entry that outlives its reason and narrows
# the surface forever (SPEC, 'the config records decisions').
printf '{"mcpServers": {"x": {"command": "c", "block": [{"tool": "T"}]}}}' > "$SB/nowhy.json"
red "validate rejects a block entry without a why" 65 "block entry for 'T' on server 'x' has no 'why'" \
  python3 "$LOADER" validate "$SB/nowhy.json"

printf '{"mcpServers": {"x": {"command": "c", "block": [{"tool": "T", "why": ""}]}}}' > "$SB/emptywhy.json"
red "validate rejects an empty why the same way" 65 "block entry for 'T' on server 'x' has no 'why'" \
  python3 "$LOADER" validate "$SB/emptywhy.json"

printf '{"mcpServers": {"x": {"command": "c", "block": [{"why": "w"}]}}}' > "$SB/notool.json"
red "a block entry without a tool name is rejected" 65 "block entry on server 'x' has no 'tool'" \
  python3 "$LOADER" validate "$SB/notool.json"

# At daemon RUNTIME the same missing why is a warning, not a startup death: rejecting at
# load would fail the repo, at startup, for a sentence someone forgot in astra
# (ROADMAP 2.2). The block still applies.
out="$SB/lenient.out"
env -u XCODE_MCP_FRONT_UPSTREAMS XCODE_MCP_FRONT_MCP_INFO="$SB/nowhy.json" \
  python3 "$LOADER" resolve >"$out" 2>&1
assert_eq "0" "$?" "resolve accepts the missing-why config instead of failing the repo at startup"
assert_contains "$out" "no 'why'" "and it says out loud what the authoring check would have rejected"

# --- the map: source-qualified renames (Phase 3) ---
mapcfg="$SB/mapcfg.json"
cat > "$mapcfg" <<'EOF'
{"mcpServers": {"x": {"command": "c", "map": [
  {"tool": "window_close", "name": "close_current_window", "why": "surface vocabulary: neither vendor's name reads right in the aggregate"}
]}}}
EOF
out="$SB/mapcfg.out"
python3 "$LOADER" validate "$mapcfg" >"$out" 2>&1
assert_eq "0" "$?" "a map entry with tool, name and why validates"
assert_contains "$out" "close_current_window" "the exposed name is shown in the listing"

printf '{"mcpServers": {"x": {"command": "c", "map": [{"tool": "t", "name": "n"}]}}}' > "$SB/mapnowhy.json"
red "validate rejects a map entry without a why" 65 "map entry for 't' on server 'x' has no 'why'" \
  python3 "$LOADER" validate "$SB/mapnowhy.json"

printf '{"mcpServers": {"x": {"command": "c", "map": [{"tool": "t", "why": "w"}]}}}' > "$SB/mapnoname.json"
red "a map entry without an exposed name is rejected" 65 "map entry for 't' on server 'x' has no 'name'" \
  python3 "$LOADER" validate "$SB/mapnoname.json"

printf '{"mcpServers": {"x": {"command": "c", "map": [{"tool": "a", "name": "same", "why": "w"}, {"tool": "b", "name": "same", "why": "w"}]}}}' > "$SB/mapdup.json"
red "two map entries claiming one exposed name are rejected" 65 "exposed name 'same' is claimed twice" \
  python3 "$LOADER" validate "$SB/mapdup.json"

printf '{"mcpServers": {"x": {"command": "c", "block": [{"tool": "t", "why": "w"}], "map": [{"tool": "t", "name": "n", "why": "w"}]}}}' > "$SB/mapblock.json"
red "a tool both blocked and renamed is a contradiction, rejected" 65 "'t' on server 'x' is both blocked and mapped" \
  python3 "$LOADER" validate "$SB/mapblock.json"

printf '{"mcpServers": {"one": {"command": "c", "map": [{"tool": "a", "name": "shared", "why": "w"}]}, "two": {"command": "c", "map": [{"tool": "b", "name": "shared", "why": "w"}]}}}' > "$SB/mapxserver.json"
red "two SERVERS claiming one exposed name are rejected at load" 65 "exposed name 'shared' is claimed by both" \
  python3 "$LOADER" validate "$SB/mapxserver.json"

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
