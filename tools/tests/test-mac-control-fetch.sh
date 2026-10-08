#!/usr/bin/env bash
# test-mac-control-fetch.sh — MacControlMCP.app installs without an authenticated gh.
#
# install.sh used to call `gh api` and `gh release download`, so a machine that had never
# run `gh auth login` died with "populate the GH_TOKEN environment variable" before it got
# to anything else (found 2026-10-07 installing swift-ios on a clean HOME). The upstream
# repo is public; fetch-app.sh now falls back to curl. This test serves a fake release from
# a local directory through file:// URLs, so nothing touches /Applications or the network.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need curl "curl ships with macOS"; need python3 "install python3"; need shasum "ships with macOS"
FETCH="$ASTRA_ROOT/tools/mcp-mac-control-mcp/fetch-app.sh"
assert_file "$FETCH" "fetch-app.sh exists"

API="$SB/api"; REL="$API/repos/acme/widget/releases"; DL="$SB/dl"
mkdir -p "$REL" "$DL" "$SB/build/MacControlMCP.app/Contents/MacOS"
printf '#!/bin/sh\necho stub\n' > "$SB/build/MacControlMCP.app/Contents/MacOS/MacControlMCP"
tar czf "$DL/MacControlMCP-9.9.9-macos-universal.tar.gz" -C "$SB/build" MacControlMCP.app
( cd "$DL" && shasum -a 256 MacControlMCP-9.9.9-macos-universal.tar.gz > MacControlMCP-9.9.9-macos-universal.tar.gz.sha256 )
python3 - "$REL/latest" "$DL" <<'PY'
import json, sys
out, dl = sys.argv[1], sys.argv[2]
json.dump({"tag_name": "v9.9.9", "assets": [
  {"name": "MacControlMCP-9.9.9-macos-universal.tar.gz", "browser_download_url": f"file://{dl}/MacControlMCP-9.9.9-macos-universal.tar.gz"},
  {"name": "MacControlMCP-9.9.9-macos-universal.tar.gz.sha256", "browser_download_url": f"file://{dl}/MacControlMCP-9.9.9-macos-universal.tar.gz.sha256"},
  {"name": "unrelated.zip", "browser_download_url": f"file://{dl}/unrelated.zip"}]}, open(out, "w"))
PY

# gh may be installed and signed in on the machine running this test; every case below must
# pass with it absent from the picture, so point it at an empty config and drop any token.
fetch() { env -u GH_TOKEN GH_CONFIG_DIR="$SB/no-gh" MAC_CONTROL_USE_CURL=1 MAC_CONTROL_REPO=acme/widget \
          GH_API_BASE="file://$API" MAC_CONTROL_APP="$SB/Apps/MacControlMCP.app" "$FETCH" "$@"; }

echo "== fresh install through curl, no gh"
assert_rc 0 "fetch-app installs from the release" fetch
assert_file "$SB/Apps/MacControlMCP.app/Contents/MacOS/MacControlMCP" "the app landed at MAC_CONTROL_APP"

echo "== a signed-in gh is not required: gh present but not authenticated"
rm -rf "$SB/Apps"
env -u GH_TOKEN -u MAC_CONTROL_USE_CURL GH_CONFIG_DIR="$SB/no-gh" MAC_CONTROL_REPO=acme/widget \
  GH_API_BASE="file://$API" MAC_CONTROL_APP="$SB/Apps/MacControlMCP.app" "$FETCH" >"$SB/ungh.out" 2>&1
assert_eq 0 "$?" "an unauthenticated gh falls back to curl"
assert_file "$SB/Apps/MacControlMCP.app/Contents/MacOS/MacControlMCP" "app installed without gh auth"

echo "== already current: nothing is downloaded or replaced"
python3 - "$SB/Apps/MacControlMCP.app/Contents/Info.plist" <<'PY'
import plistlib, sys
plistlib.dump({"CFBundleShortVersionString": "9.9.9"}, open(sys.argv[1], "wb"))
PY
touch -t 200001010000 "$SB/Apps/MacControlMCP.app/Contents/MacOS/MacControlMCP"
fetch >"$SB/cur.out" 2>&1
assert_contains "$SB/cur.out" "already at latest" "reports the app is current"
[ "$(stat -f %Sm -t %Y "$SB/Apps/MacControlMCP.app/Contents/MacOS/MacControlMCP")" = 2000 ] \
  && pass "the installed app was not replaced" || fail "an up-to-date app was reinstalled"

echo "== RED controls"
rm -rf "$SB/Apps"; mkdir -p "$SB/Apps/MacControlMCP.app/Contents"; echo keep > "$SB/Apps/MacControlMCP.app/Contents/marker"
printf 'tampered' >> "$DL/MacControlMCP-9.9.9-macos-universal.tar.gz"
red "a checksum mismatch refuses to install" 65 "sha256 mismatch" fetch
assert_file "$SB/Apps/MacControlMCP.app/Contents/marker" "the previous app survives a failed update"
red "an unreachable API fails loudly" 69 "could not read the latest release" \
  env -u GH_TOKEN GH_CONFIG_DIR="$SB/no-gh" MAC_CONTROL_USE_CURL=1 MAC_CONTROL_REPO=acme/widget \
      GH_API_BASE="file://$SB/nowhere" MAC_CONTROL_APP="$SB/Apps/MacControlMCP.app" "$FETCH"
finish
