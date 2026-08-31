#!/usr/bin/env bash
# test-tooljson.sh — the tool.json reader (Phase 6.1 of the tool-template roadmap).
#
# Seven tools/mcp-*/tool.json descriptors have existed since before this project and
# NOTHING read them (INVENTORY.md: "seven dead files"). The reader converts them into a
# validated registry: every descriptor either parses into a known shape or fails with a
# named reason. Dependencies are declared BY ECOSYSTEM (brew:, npm:, uv:, human:) —
# brew-only under-declares more than half of what is here, and 'a human must grant this
# in System Settings' is a real dependency class on this machine.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need python3 "xcode-select --install"
READER="$HERE/../lib/tooljson.py"

# --- the seven real descriptors all validate (dead files become a live registry) ---
out="$SB/list.out"
python3 "$READER" list >"$out" 2>"$SB/list.err"
assert_eq "0" "$?" "every existing tool.json in the repo validates"
for t in mcp-xcode mcp-kickerd mcp-ios-simulator mcp-mobile-mcp mcp-mac-control-mcp mcp-xcode-mcp-server mcp-XcodeBuildMCP; do
  assert_contains "$out" "$t" "the registry lists $t"
done
assert_contains "$SB/list.err" "legacy dependency" \
  "bare legacy dependency tokens are accepted but reported, so they get migrated"

# --- deps are resolvable by ecosystem ---
out="$SB/deps.out"
python3 "$READER" deps mcp-ios-simulator >"$out" 2>&1
assert_eq "0" "$?" "deps resolves a named tool"
assert_contains "$out" "npm: ios-simulator-mcp" "an npm-qualified dependency lands in the npm group"

# --- the rejection surface, each with a named reason ---
D="$SB/fake-tool"
mkdir -p "$D"

printf '{"description": "d", "provides": "cli", "dependencies": []}' > "$D/tool.json"
red "a descriptor without a name is rejected" 65 "has no 'name'" \
  python3 "$READER" validate "$D/tool.json"

printf '{"name": "other-name", "description": "d", "provides": "cli", "dependencies": []}' > "$D/tool.json"
red "a name that does not match its directory is rejected" 65 "does not match its directory" \
  python3 "$READER" validate "$D/tool.json"

printf '{"name": "fake-tool", "provides": "cli", "dependencies": []}' > "$D/tool.json"
red "a descriptor without a description is rejected" 65 "has no 'description'" \
  python3 "$READER" validate "$D/tool.json"

printf '{"name": "fake-tool", "description": "d", "provides": "mcp-server", "dependencies": []}' > "$D/tool.json"
red "provides mcp-server without a server name is rejected" 65 "provides 'mcp-server' but names no 'server'" \
  python3 "$READER" validate "$D/tool.json"

printf '{"name": "fake-tool", "description": "d", "provides": "cli", "dependencies": ["cargo:ripgrep"]}' > "$D/tool.json"
red "an unknown dependency ecosystem is rejected by name" 65 "unknown dependency ecosystem 'cargo'" \
  python3 "$READER" validate "$D/tool.json"

printf '{"name": "fake-tool", "description": "d", "provides": "cli", "dependencies": [], "backed_by": "tools/no-such-dir"}' > "$D/tool.json"
red "a backed_by that does not exist is rejected" 65 "backed_by 'tools/no-such-dir' does not exist" \
  python3 "$READER" validate "$D/tool.json"

# Third-party adoption fields (ROADMAP phase 6): source + version + digest travel
# together or not at all — a coordinate without a pin is an unrepeatable install.
printf '{"name": "fake-tool", "description": "d", "provides": "cli", "dependencies": [], "source": "github:someone/thing"}' > "$D/tool.json"
red "a source coordinate without a version pin is rejected" 65 "'source' requires 'version'" \
  python3 "$READER" validate "$D/tool.json"

printf '{"name": "fake-tool", "description": "d", "provides": "cli", "dependencies": ["human:Full Disk Access for Mail"], "source": "github:someone/thing", "version": "1.2.3", "digest": "sha256:abc"}' > "$D/tool.json"
out="$SB/ok.out"
python3 "$READER" validate "$D/tool.json" >"$out" 2>&1
assert_eq "0" "$?" "a fully-pinned third-party descriptor with a human-grant dependency validates"
assert_contains "$out" "human: Full Disk Access for Mail" \
  "the human-grant dependency class is first-class, not an afterthought"

finish
