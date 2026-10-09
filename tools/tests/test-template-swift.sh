#!/usr/bin/env bash
# TIER: slow — three template installs with real agent-CLI config writes, about 15s; needs no machine state
# test-template-swift.sh — the swift-ios and mac-swift templates install, re-install and uninstall
# cleanly into a fresh repo on a machine with no Homebrew work to do.
#
# These two templates are the ones the Maharam repos use and they had no committed test: a hand run
# into a pot-mhm clone was the only evidence they worked. The machine-level steps are neutralised
# without faking the code under test:
#   - the MacControlMCP download comes from a fake release served out of a local directory;
#   - ASTRA_SKIP_MACHINE_DEPS=1 skips the brew and pipx install of idb (the one step that would change
#     the machine), and everything else, including the claude CLI that writes the .mcp.json entries,
#     is the real thing.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need claude "npm install -g @anthropic-ai/claude-code"; need jq "brew install jq"; need python3 "install python3"; need tar "ships with macOS"; need shasum "ships with macOS"
TEMPLATE="$ASTRA_ROOT/tools/lib/template.py"

# ---- a fake MacControlMCP release ----
API="$SB/api"; DL="$SB/dl"; mkdir -p "$API/repos/acme/widget/releases" "$DL" "$SB/build/MacControlMCP.app/Contents/MacOS" "$SB/home"
printf '#!/bin/sh\necho stub\n' > "$SB/build/MacControlMCP.app/Contents/MacOS/MacControlMCP"
chmod +x "$SB/build/MacControlMCP.app/Contents/MacOS/MacControlMCP"
tar czf "$DL/MacControlMCP-9.9.9-macos-universal.tar.gz" -C "$SB/build" MacControlMCP.app
( cd "$DL" && shasum -a 256 MacControlMCP-9.9.9-macos-universal.tar.gz > MacControlMCP-9.9.9-macos-universal.tar.gz.sha256 )
python3 - "$API/repos/acme/widget/releases/latest" "$DL" <<'PY'
import json, sys
out, dl = sys.argv[1], sys.argv[2]
json.dump({"tag_name": "v9.9.9", "assets": [
  {"name": "MacControlMCP-9.9.9-macos-universal.tar.gz", "browser_download_url": f"file://{dl}/MacControlMCP-9.9.9-macos-universal.tar.gz"},
  {"name": "MacControlMCP-9.9.9-macos-universal.tar.gz.sha256", "browser_download_url": f"file://{dl}/MacControlMCP-9.9.9-macos-universal.tar.gz.sha256"}]}, open(out, "w"))
PY
APP="$SB/Apps/MacControlMCP.app"

env_run() {  # run a command with the sandbox machine environment
  env -u GH_TOKEN -u ASTRA_SOURCE -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME \
      HOME="$SB/home" GH_CONFIG_DIR="$SB/no-gh" MAC_CONTROL_USE_CURL=1 MAC_CONTROL_REPO=acme/widget \
      GH_API_BASE="file://$API" MAC_CONTROL_APP="$APP" ASTRA_SKIP_MACHINE_DEPS=1 "$@"
}
new_repo() { mkdir -p "$1"; git -C "$1" init -q; git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; }
servers() { jq -r '.mcpServers | keys | join(",")' "$1/.mcp.json" 2>/dev/null; }
tree_sum() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort | xargs shasum | shasum | cut -c1-40 ); }

echo "== swift-ios"
IOS="$SB/ios"; new_repo "$IOS"
env_run python3 "$TEMPLATE" install swift-ios --into "$IOS" > "$SB/ios.out" 2>&1; rc=$?
assert_eq 0 "$rc" "swift-ios installs"
[ "$rc" = 0 ] || sed 's/^/        /' "$SB/ios.out" | tail -n 15
assert_eq "ios-simulator,mac-control-mcp,xcode-combined" "$(servers "$IOS")" "exactly the three MCP servers: the aggregator, mac control, the simulator"
assert_eq "$APP/Contents/MacOS/MacControlMCP" "$(jq -r '.mcpServers["mac-control-mcp"].command' "$IOS/.mcp.json")" "the mac-control entry points at the app that was downloaded"
assert_eq "http://127.0.0.1:8767/mcp" "$(jq -r '.mcpServers["xcode-combined"].url' "$IOS/.mcp.json")" "the Xcode aggregator is one HTTP entry, not a direct spawn"
for s in ios-ui-driving ponytail ponytail-audit asd-ste100 prose humanizer convocation; do
  assert_file "$IOS/.claude/skills/$s/SKILL.md" "skill installed: $s"
done
for d in writing convocation act-first; do assert_file "$IOS/.doctrine/$d.md" "doctrine installed: $d"; done
assert_file "$IOS/.astra/convocation/panel" "the convocation dispatcher is in the repo"
assert_file "$IOS/.astra/dedup-scan/dedup-scan" "the Swift quality tools are in the repo"
assert_contains "$SB/ios.out" "MACHINE axe" "axe is named as a once-per-machine install, not run"
assert_not_contains "$SB/ios.out" "periphery" "periphery is not part of the template (it is an opt-in tool)"
assert_eq "swift-ios" "$(jq -r '.template_tools | keys | join(",")' "$IOS/.astra/manifest.json")" "the manifest records the template"
# Every agent gets every server. Qwen and Codex read a project config INSTEAD of the user-level one, so a
# server missing from either is missing in that agent for the whole repo.
assert_eq "ios-simulator,mac-control-mcp,xcode-combined" "$(jq -r '.mcpServers | keys | join(",")' "$IOS/.qwen/settings.json")" "Qwen has all three servers"
for srv in xcode-combined mac-control-mcp ios-simulator; do
  assert_contains "$IOS/.codex/config.toml" "[mcp_servers.$srv]" "Codex has $srv"
done
# The manifest records the toolbox's own path when the repo is not beside it, which a sandbox never is;
# test-portable-install.sh covers the relative form. Everything else must be free of a machine's paths.
leaks="$(cd "$IOS" && grep -rIn 'svnCheckouts\|/Users/' . --exclude-dir=.git --exclude=manifest.json 2>/dev/null)"
assert_empty "$leaks" "no foreign path in anything it installed"

echo "== re-running is the update path and changes nothing when nothing moved"
before="$(tree_sum "$IOS")"
env_run python3 "$TEMPLATE" install swift-ios --into "$IOS" > "$SB/ios2.out" 2>&1; rc=$?
assert_eq 0 "$rc" "the second install succeeds"
assert_eq "$before" "$(tree_sum "$IOS")" "and leaves every file in the repo byte-identical"

echo "== uninstall removes it"
env_run python3 "$TEMPLATE" uninstall swift-ios --into "$IOS" > "$SB/ios-un.out" 2>&1; rc=$?
assert_eq 0 "$rc" "swift-ios uninstalls"
assert_no_file "$IOS/.claude/skills/ios-ui-driving" "the iOS UI-driving skill is gone"
assert_no_file "$IOS/.astra/convocation" "the repo-side tools are gone"
if [ -f "$IOS/.mcp.json" ]; then assert_empty "$(servers "$IOS")" "no MCP server entry is left behind"; else pass "the .mcp.json it created is gone"; fi
assert_file "$APP/Contents/MacOS/MacControlMCP" "the shared app is NOT removed by a repo uninstall"

echo "== mac-swift: the same minus the simulator pieces"
MAC="$SB/mac"; new_repo "$MAC"
env_run python3 "$TEMPLATE" install mac-swift --into "$MAC" > "$SB/mac.out" 2>&1; rc=$?
assert_eq 0 "$rc" "mac-swift installs"
assert_eq "mac-control-mcp,xcode-combined" "$(servers "$MAC")" "two MCP servers, no simulator"
assert_eq "mac-control-mcp,xcode-combined" "$(jq -r '.mcpServers | keys | join(",")' "$MAC/.qwen/settings.json")" "and the same two in Qwen"
assert_no_file "$MAC/.claude/skills/ios-ui-driving" "no iOS UI-driving skill"
assert_file "$MAC/.claude/skills/ponytail/SKILL.md" "the Swift quality skills are there"
assert_file "$MAC/.doctrine/act-first.md" "and the base doctrine"
assert_not_contains "$SB/mac.out" "MACHINE axe" "axe is not part of mac-swift"
assert_eq "mac-swift" "$(jq -r '.template_tools | keys | join(",")' "$MAC/.astra/manifest.json")" "the manifest records the template"

echo "== kicker-dev uses the combined Xcode front"
KICKER="$SB/kicker"; new_repo "$KICKER"
env_run python3 "$TEMPLATE" install kicker-dev --into "$KICKER" > "$SB/kicker.out" 2>&1; rc=$?
assert_eq 0 "$rc" "kicker-dev installs"
assert_eq "kickerd,mac-control-mcp,xcode-combined" "$(servers "$KICKER")" "kicker-dev has the combined front and no direct Xcode server"
assert_eq "http://127.0.0.1:8767/mcp" "$(jq -r '.mcpServers["xcode-combined"].httpUrl' "$KICKER/.gemini/settings.json")" "Gemini has the combined front"
assert_not_contains "$KICKER/.codex/config.toml" "[mcp_servers.xcode]" "Codex has no direct Apple bridge"

echo "== RED controls"
red "an unknown template is refused" 66 "no such template or tool" env_run python3 "$TEMPLATE" install no-such-template --into "$MAC"
red "installing into a directory that is not there is refused" 66 "no such" env_run python3 "$TEMPLATE" install mac-swift --into "$SB/missing"
finish
