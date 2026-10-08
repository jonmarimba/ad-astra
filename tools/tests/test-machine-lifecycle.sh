#!/usr/bin/env bash
# TIER: slow — installs, upgrades and uninstalls a dozen tools against a throwaway machine; a few seconds
# test-machine-lifecycle.sh — the machine-level lifecycle, run for real against an empty, throwaway machine.
#
# Every other test neutralises brew, pipx and uv, so "does astra install, update and remove software"
# had only been checked by reading scripts. This builds a machine from nothing in a temp directory:
#   - a fake Homebrew (tools/tests/fakeworld/brew) with its own prefix, cellar and call log;
#   - fake pipx and uv that install shims into a sandbox ~/.local/bin;
#   - a sandbox Applications directory for MacControlMCP.app, served from a fake release;
#   - a sandbox HOME, and ASTRA_PATH set to exactly those directories plus the system ones, so
#     NOTHING installed on the machine running the test can answer for the fake machine.
# Then it runs `astra upgrade` on the empty machine and checks every formula, tool and app really
# arrived, runs it again and checks everything was upgraded without being reinstalled or re-downloaded,
# and runs the uninstallers and checks they remove exactly what they promise. The fakes fail loudly
# on any verb the installers are not supposed to use, so a new, unreviewed use of brew breaks this test.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need claude "npm install -g @anthropic-ai/claude-code"; need tar "ships with macOS"; need shasum "ships with macOS"; need curl "ships with macOS"; need python3 "install python3"
FAKES="$ASTRA_ROOT/tools/tests/fakeworld"
W="$SB/world"; HOME_W="$W/home"; APPS="$W/Applications"; TOOLBOX="$W/astra"
mkdir -p "$HOME_W" "$APPS" "$TOOLBOX"
# What the REAL machine looks like before, so the end of the run can prove it was not touched.
real_snapshot() {
  stat -f '%m %N' /Applications/MacControlMCP.app 2>&1
  ls -la "$REAL_HOME/.local/bin/idb" "$REAL_HOME/.local/bin/graphify" "$REAL_HOME/.cache/whisper/ggml-base.en.bin" 2>&1
}
REAL_HOME="$HOME"
real_before="$(real_snapshot)"
( cd "$ASTRA_ROOT" && { git ls-files -z --recurse-submodules; git ls-files -z --others --exclude-standard; } | tar --null -T - -cf - ) | tar -xf - -C "$TOOLBOX"

# ---- the machine's PATH: the fakes, what they install, and the system directories. Nothing else. ----
# The agent CLI is a machine tool the bundle needs to write config; it is a native binary, so a symlink
# makes it the one real program on an otherwise fake machine.
mkdir -p "$W/sys"   # the real agent CLI is linked in later, for the template step
WPATH="$FAKES:$W/brew/prefix/bin:$HOME_W/.local/bin:$W/sys:/usr/bin:/bin:/usr/sbin:/sbin"
world() {  # run a command inside the throwaway machine
  env -i HOME="$HOME_W" FAKE_WORLD="$W" PATH="$WPATH" ASTRA_PATH="$WPATH" TMPDIR="$SB" \
      MAC_CONTROL_APP="$APPS/MacControlMCP.app" MAC_CONTROL_USE_CURL=1 MAC_CONTROL_REPO=acme/widget \
      GH_API_BASE="file://$W/api" GH_CONFIG_DIR="$W/no-gh" \
      SPEECH_BEE_MODEL_URL_BASE="file://$W/hub" "$@"
}

# ---- a fake MacControlMCP release and a fake whisper model hub ----
mkdir -p "$W/api/repos/acme/widget/releases" "$W/dl" "$W/b/MacControlMCP.app/Contents/MacOS" "$W/hub"
printf '#!/bin/sh\necho stub\n' > "$W/b/MacControlMCP.app/Contents/MacOS/MacControlMCP"; chmod +x "$W/b/MacControlMCP.app/Contents/MacOS/MacControlMCP"
# a real app carries its version in Info.plist; that is how the downloader knows it is already current
python3 -c 'import plistlib,sys; plistlib.dump({"CFBundleShortVersionString": "9.9.9"}, open(sys.argv[1], "wb"))' "$W/b/MacControlMCP.app/Contents/Info.plist"
tar czf "$W/dl/MacControlMCP-9.9.9-macos-universal.tar.gz" -C "$W/b" MacControlMCP.app
( cd "$W/dl" && shasum -a 256 MacControlMCP-9.9.9-macos-universal.tar.gz > MacControlMCP-9.9.9-macos-universal.tar.gz.sha256 )
python3 - "$W/api/repos/acme/widget/releases/latest" "$W/dl" <<'PY'
import json, sys
out, dl = sys.argv[1], sys.argv[2]
json.dump({"tag_name": "v9.9.9", "assets": [
  {"name": "MacControlMCP-9.9.9-macos-universal.tar.gz", "browser_download_url": f"file://{dl}/MacControlMCP-9.9.9-macos-universal.tar.gz"},
  {"name": "MacControlMCP-9.9.9-macos-universal.tar.gz.sha256", "browser_download_url": f"file://{dl}/MacControlMCP-9.9.9-macos-universal.tar.gz.sha256"}]}, open(out, "w"))
PY
printf 'not a real model, but a file whisper-cli never reads in this test' > "$W/hub/ggml-base.en.bin"

TOOLS="axe periphery frame-review botline botmsg geo-evidence speech-bee graphify-repo pdf-sidecars harness-settings convocation agent-sync mcp-ios-simulator mcp-mac-control-mcp xcode-mcp-front"
NTOOLS="$(echo $TOOLS | wc -w | tr -d ' ')"
brew_state() { ls "$W/brew/state" 2>/dev/null | sort | tr '\n' ' '; }
version_of() { cat "$W/brew/state/$1" 2>/dev/null; }

# An orphaned dependency the machine's owner keeps, which real Homebrew would autoremove during any
# upgrade or uninstall. No astra tool may let that happen to formulae it did not install.
mkdir -p "$W/brew/state"; echo 1 > "$W/brew/state/kept-orphan"; : > "$W/brew/state/.orphan-kept-orphan"

echo "== the machine starts empty, and the real one cannot answer for it"
assert_eq "kept-orphan " "$(brew_state)" "only the owner's own orphan is installed; nothing from astra"
assert_eq "" "$(world sh -c 'command -v axe; command -v periphery; command -v idb; command -v ffmpeg' 2>/dev/null)" "axe, periphery, idb and ffmpeg are not found, whatever this machine has"
red "the fake brew refuses a verb nothing should use" 99 "unsupported verb" world brew frobnicate
red "the fake pipx refuses one too" 99 "unsupported verb" world pipx run something
red "and the fake uv" 99 "unsupported verb" world uv pip install x

echo "== astra upgrade installs everything onto the empty machine"
world "$TOOLBOX/tools/astra" upgrade --list > "$SB/plan.out" 2>&1
for t in $TOOLS; do assert_contains "$SB/plan.out" "$t" "the plan includes $t"; done
world "$TOOLBOX/tools/astra" upgrade $TOOLS > "$SB/up1.out" 2>&1; rc=$?
assert_eq 0 "$rc" "astra upgrade succeeds on an empty machine"
[ "$rc" = 0 ] || tail -n 25 "$SB/up1.out" | sed 's/^/        /'
assert_contains "$SB/up1.out" "$NTOOLS ok, 0 failed" "all $NTOOLS tools report ok"
# Every formula each tool's own Brewfile names must now exist, whatever those files say today.
missing=""
for t in axe periphery frame-review botline botmsg geo-evidence speech-bee graphify-repo pdf-sidecars harness-settings agent-sync; do
  for f in $(sed -n 's/^[[:space:]]*brew[[:space:]]*"\([^"]*\)".*/\1/p' "$TOOLBOX/tools/$t/Brewfile" 2>/dev/null); do
    [ -f "$W/brew/state/${f##*/}" ] || missing="$missing $t:$f"
  done
done
assert_empty "$missing" "every formula in every Brewfile is installed"
assert_eq 1 "$([ -f "$W/brew/state/axe" ] && echo 1)" "axe itself arrived (a tap formula, installed by name)"
assert_eq 1 "$([ -f "$W/brew/state/idb-companion" ] && echo 1)" "idb-companion arrived"
assert_file "$W/brew/state/node" "node arrived too: the simulator server runs through npx, and nothing else on this machine provides it"
assert_file "$W/brew/prefix/bin/npx" "with npx beside it"
assert_file "$HOME_W/.local/bin/idb" "pipx installed the idb CLI"
assert_file "$W/brew/prefix/bin/idb" "and it was linked into Homebrew's bin, where GUI-spawned servers look"
assert_file "$W/uv/osxphotos" "uv installed osxphotos"
assert_file "$W/uv/graphifyy" "uv installed graphify"
assert_file "$W/uv/marker-pdf" "uv installed marker for pdf-sidecars"
assert_contains "$W/pip.log" "install --user --upgrade --quiet tomlkit" "pip installed tomlkit for harness-settings, through the fake pip"
assert_eq "tomlkit-ok" "$(world python3 -c 'import tomlkit' && echo tomlkit-ok)" "and the machine can now import it"
assert_file "$W/brew/prefix/bin/claude" "convocation installed the claude CLI through npm"
assert_file "$W/brew/prefix/bin/codex" "and codex"
assert_file "$W/brew/state/qwen-code" "and qwen through brew, the method this machine already uses"
assert_eq 0 "$(grep -c 'rsync' "$W/brew/log" | tr -d ' ' | sed 's/^[1-9].*/0/')" "(agent-sync's deps ran against a toolbox copy with no .git without failing on the submodule)"
assert_file "$APPS/MacControlMCP.app/Contents/MacOS/MacControlMCP" "MacControlMCP.app was downloaded into the sandbox Applications directory"
assert_file "$HOME_W/.cache/whisper/ggml-base.en.bin" "the whisper model was fetched into the sandbox HOME"
assert_not_contains "$W/brew/log" "unsupported" "no installer used a brew verb the fake does not implement"

echo "== a second upgrade upgrades in place: nothing reinstalled, nothing re-downloaded"
formulas_before="$(brew_state)"
v_axe="$(version_of axe)"
world "$TOOLBOX/tools/astra" upgrade $TOOLS > "$SB/up2.out" 2>&1; rc=$?
assert_eq 0 "$rc" "the second upgrade succeeds"
assert_eq "$formulas_before" "$(brew_state)" "the set of installed formulae is unchanged"
assert_eq "$((v_axe + 1))" "$(version_of axe)" "axe was upgraded once"
assert_contains "$SB/up2.out" "already at latest" "the app was recognised as current and not downloaded again"
assert_eq 1 "$(grep -c 'install' "$W/pipx.log" 2>/dev/null)" "idb was installed exactly once across both runs (the second only upgraded)"
assert_contains "$W/pipx.log" "upgrade fb-idb" "and the second run upgraded it"

echo "== uninstalling keeps shared software unless told to remove it"
world "$TOOLBOX/tools/axe/uninstall.sh" > "$SB/un1.out" 2>&1; rc=$?
assert_eq 0 "$rc" "axe uninstall succeeds"
assert_file "$W/brew/state/axe" "without --deps the formula is KEPT (other repos may be driving the simulator with it)"
world "$TOOLBOX/tools/axe/uninstall.sh" --deps > "$SB/un2.out" 2>&1; rc=$?
assert_eq 0 "$rc" "axe uninstall --deps succeeds"
assert_no_file "$W/brew/state/axe" "--deps removes the formula"
assert_no_file "$W/brew/prefix/bin/axe" "and its binary"
assert_file "$W/brew/state/periphery" "while a different tool's formula is untouched"
world "$TOOLBOX/tools/periphery/uninstall.sh" --deps > "$SB/un3.out" 2>&1
assert_no_file "$W/brew/state/periphery" "periphery --deps is removed as well"

echo "== and an upgrade after an uninstall puts it back"
world "$TOOLBOX/tools/astra" upgrade axe > "$SB/up3.out" 2>&1; rc=$?
assert_eq 0 "$rc" "upgrade reinstalls a removed tool"
assert_file "$W/brew/state/axe" "axe is back"
assert_file "$W/brew/state/kept-orphan" "an unrelated orphaned formula survived every upgrade and uninstall (real brew would have autoremoved it)"
# `bundle list` printed an "==> Auto-updating Homebrew..." banner on stdout, as real brew can; no word of it
# may reach `brew upgrade` as if it were a formula name.
assert_not_contains "$W/brew/log" "brew upgrade ==>" "no banner word was handed to brew upgrade as a formula name"
assert_not_contains "$W/brew/log" "brew upgrade Auto-updating" "and neither was part of the banner text"

echo "== wrapper apps: built once, never rebuilt, because a rebuild destroys the permission grants they hold"
# handlebars builds a real signed .app in the toolbox copy with the real wrap-in-app and codesign.
world "$TOOLBOX/tools/handlebars/install.sh" > "$SB/hb1.out" 2>&1; rc=$?
assert_eq 0 "$rc" "handlebars installs: brew deps, then the real wrapper app"
[ "$rc" = 0 ] || tail -n 12 "$SB/hb1.out" | sed 's/^/        /'
HB="$TOOLBOX/tools/handlebars/Handlebars.app"
assert_dir "$HB" "Handlebars.app was built"
codesign --verify --deep "$HB" >/dev/null 2>&1 && pass "and it is validly signed" || fail "the app's signature does not verify"
hb_hash="$(find "$HB" -type f -exec shasum {} + | sort | shasum | cut -c1-40)"
world "$TOOLBOX/tools/handlebars/install.sh" > "$SB/hb2.out" 2>&1; rc=$?
assert_eq 0 "$rc" "installing again succeeds"
assert_contains "$SB/hb2.out" "not rebuilding" "and says it left the existing app alone"
assert_eq "$hb_hash" "$(find "$HB" -type f -exec shasum {} + | sort | shasum | cut -c1-40)" "every byte of the app is unchanged, so its permission grants survive"
world "$TOOLBOX/tools/handlebars/uninstall.sh" > "$SB/hb3.out" 2>&1; rc=$?
assert_eq 0 "$rc" "uninstall succeeds"
assert_no_file "$HB" "and removes the app"

echo "== a template install in this world installs the software its tools need, and a repo uninstall leaves it"
# The fake agent CLIs convocation's deps put in the prefix would be driven by the bundle's `mcp add` steps
# (and do nothing), and the fake claude would shadow the real one. Remove them: on this machine the only
# agent CLI is the real claude, and the bundle writes the other agents' config files itself.
rm -f "$W/brew/prefix/bin/claude" "$W/brew/prefix/bin/codex" "$W/brew/prefix/bin/qwen"
ln -sf "$(command -v claude)" "$W/sys/claude"
# Remove what the upgrade put there, so the template install has to bring it back through the real
# ios-simulator and mac-control installers, with no skip knob.
world pipx uninstall fb-idb; world brew uninstall idb-companion >/dev/null 2>&1
rm -rf "$APPS/MacControlMCP.app" "$W/brew/prefix/bin/idb"
assert_no_file "$HOME_W/.local/bin/idb" "idb is gone before the template install"
REPO="$W/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
world python3 "$TOOLBOX/tools/lib/template.py" install swift-ios --into "$REPO" > "$SB/tpl1.out" 2>&1; rc=$?
assert_eq 0 "$rc" "swift-ios installs into a repo on the throwaway machine"
if [ "$rc" != 0 ]; then
  grep -m3 "FAILED" "$SB/tpl1.out" | sed "s/^/        /"
  # the template rolled the repo back, so re-run the failing member alone and show what it saw
  ( cd "$REPO" && world "$TOOLBOX/tools/mcp-mac-control-mcp/install.sh" --into "$REPO" 2>&1 | tail -n 8 | sed 's/^/        | /'; echo "        .mcp.json: $(tr -d '\n' < "$REPO/.mcp.json" 2>&1 | cut -c1-200)" )
fi
[ "$rc" = 0 ] || tail -n 15 "$SB/tpl1.out" | sed 's/^/        /'
assert_file "$W/brew/state/idb-companion" "the installer brought idb-companion back through brew"
assert_file "$HOME_W/.local/bin/idb" "and the idb CLI through pipx"
assert_file "$APPS/MacControlMCP.app/Contents/MacOS/MacControlMCP" "and downloaded the app"
assert_eq "ios-simulator,mac-control-mcp,xcode-combined" "$(jq -r '.mcpServers | keys | join(",")' "$REPO/.mcp.json")" "the repo's three MCP entries are written"
assert_eq "$APPS/MacControlMCP.app/Contents/MacOS/MacControlMCP" "$(jq -r '.mcpServers["mac-control-mcp"].command' "$REPO/.mcp.json")" "the entry points at the sandbox app, the one the installer chose"
installs_before="$(grep -c '^brew install' "$W/brew/log")"
world python3 "$TOOLBOX/tools/lib/template.py" install swift-ios --into "$REPO" > "$SB/tpl2.out" 2>&1; rc=$?
assert_eq 0 "$rc" "re-running the template (the update path) succeeds"
assert_eq "$installs_before" "$(grep -c '^brew install' "$W/brew/log")" "and installs nothing that is already there"
world python3 "$TOOLBOX/tools/lib/template.py" uninstall swift-ios --into "$REPO" > "$SB/tpl3.out" 2>&1; rc=$?
assert_eq 0 "$rc" "the repo uninstall succeeds"
assert_no_file "$REPO/.claude/skills/ios-ui-driving" "the repo's files are gone"
assert_file "$W/brew/state/idb-companion" "but the machine software it installed stays: it is shared, so no repo uninstall may remove it"
assert_file "$HOME_W/.local/bin/idb" "idb stays"
assert_file "$APPS/MacControlMCP.app/Contents/MacOS/MacControlMCP" "and the app stays"

echo "== the real machine was not touched"
assert_eq "$real_before" "$(real_snapshot)" "the real /Applications app, ~/.local/bin and model cache are exactly as they were"

echo "== a guard: no installer can bypass the world's PATH"
# Every script that puts Homebrew on PATH must let ASTRA_PATH replace it, or an empty fake machine
# would quietly see the real one. A new script that forgets fails here.
leaks="$(cd "$ASTRA_ROOT/tools" && git ls-files | grep -v 'tool-templates/\|^vendor/' | while IFS= read -r f; do
  grep -nH 'export PATH="[^"]*/opt/homebrew/bin' "$f" 2>/dev/null | grep -v 'ASTRA_PATH'; done)"
assert_empty "$leaks" "every export PATH that names Homebrew honours ASTRA_PATH"
[ -z "$leaks" ] || printf '%s\n' "$leaks" | sed 's/^/        /' | cut -c1-160

finish
