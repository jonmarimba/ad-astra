#!/usr/bin/env bash
# fetch-app.sh — install or update MacControlMCP.app from the latest upstream release.
#
# Split out of install.sh so it can be tested without touching /Applications. It used to
# require an authenticated `gh`, which a machine that has never run `gh auth login` does
# not have: the install died with "populate the GH_TOKEN environment variable" before it
# reached anything portable. The upstream repository is public, so this uses `gh` only
# when it is installed AND signed in, and plain curl against the public API otherwise.
#
# Environment (all optional):
#   MAC_CONTROL_APP        where the app lives            (default /Applications/MacControlMCP.app)
#   MAC_CONTROL_REPO       owner/name of the release repo (default AdelElo13/mac-control-mcp)
#   GH_API_BASE            API root                       (default https://api.github.com)
#   MAC_CONTROL_USE_CURL=1 never use gh, even when signed in
#   GH_TOKEN               sent as a bearer token on the curl path, for the rate limit
#
# The app is Developer ID-signed (team A3W973JZ49), so its TCC grants survive same-team updates.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

APP="${MAC_CONTROL_APP:-/Applications/MacControlMCP.app}"
REPO_GH="${MAC_CONTROL_REPO:-AdelElo13/mac-control-mcp}"
API="${GH_API_BASE:-https://api.github.com}"
command -v python3 >/dev/null || { echo "mac-control-mcp: FAIL — python3 missing" >&2; exit 69; }
command -v shasum >/dev/null || { echo "mac-control-mcp: FAIL — shasum missing" >&2; exit 69; }

use_gh=0
if [ "${MAC_CONTROL_USE_CURL:-0}" != 1 ] && command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then use_gh=1; fi
auth=(); [ -n "${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GH_TOKEN")

if [ "$use_gh" = 1 ]; then
  RELEASE="$(gh api "repos/$REPO_GH/releases/latest")"
else
  command -v curl >/dev/null || { echo "mac-control-mcp: FAIL — neither a signed-in gh nor curl is available" >&2; exit 69; }
  RELEASE="$(curl -fsSL "${auth[@]+"${auth[@]}"}" "$API/repos/$REPO_GH/releases/latest")" \
    || { echo "mac-control-mcp: FAIL — could not read the latest release of $REPO_GH from $API" >&2; exit 69; }
fi
LATEST="$(printf '%s' "$RELEASE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))')"
[ -n "$LATEST" ] || { echo "mac-control-mcp: FAIL — could not read the latest release of $REPO_GH" >&2; exit 69; }
HAVE="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo none)"

if [ "v$HAVE" = "$LATEST" ]; then
  echo "mac-control-mcp: MacControlMCP.app already at latest ($LATEST)"
  exit 0
fi

echo "mac-control-mcp: installing MacControlMCP.app $LATEST (have: $HAVE)"
WORK="$(mktemp -d -t mac-control-mcp)"
trap 'rm -rf "$WORK"' EXIT
# One "name url" line per wanted asset.
printf '%s' "$RELEASE" | python3 -c '
import fnmatch, json, sys
for a in json.load(sys.stdin).get("assets", []):
    if fnmatch.fnmatch(a["name"], "MacControlMCP-*-macos-universal.tar.gz") or fnmatch.fnmatch(a["name"], "*.sha256"):
        print(a["name"], a["browser_download_url"])' > "$WORK/assets.txt"
[ -s "$WORK/assets.txt" ] || { echo "mac-control-mcp: FAIL — release $LATEST lists no app archive" >&2; exit 69; }
while read -r name url; do
  curl -fsSL "${auth[@]+"${auth[@]}"}" -o "$WORK/$name" "$url" \
    || { echo "mac-control-mcp: FAIL — download of $name" >&2; exit 69; }
done < "$WORK/assets.txt"
( cd "$WORK" && shasum -a 256 -c ./*.sha256 ) \
  || { echo "mac-control-mcp: FAIL — sha256 mismatch on downloaded app; NOT installing" >&2; exit 65; }
tar xzf "$WORK"/MacControlMCP-*-macos-universal.tar.gz -C "$WORK"
[ -d "$WORK/MacControlMCP.app" ] || { echo "mac-control-mcp: FAIL — archive did not contain MacControlMCP.app" >&2; exit 65; }
mkdir -p "$(dirname "$APP")"   # a per-user ~/Applications may not exist yet
rm -rf "$APP"
mv "$WORK/MacControlMCP.app" "$APP"
echo "mac-control-mcp: installed $LATEST -> $APP (running sessions keep the old binary until their server respawns)"
