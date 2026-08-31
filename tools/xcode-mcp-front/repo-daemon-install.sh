#!/bin/bash
# repo-daemon-install.sh — install an AUTONOMOUS per-repo copy of the MCP front daemon.
#
# Phase 5 of the tool-template roadmap, per Jonathan's design (2026-08-31), which
# overrides the panel's shared-broker recommendation: "I'd strongly prefer each install
# in a given repo to be autonomous. That way, one thing failing doesn't fuck all my
# projects at once." Each repo gets its own clone of the wrapper under .astra/mcp-front
# — APFS clones (cp -c), like a gentleman — its own launchd plist, and a run script
# that resolves port collisions at launch (see repo-daemon-run.sh).
#
# What this does NOT automate: TCC. A config whose upstream carries the require_xcode
# quirk needs the approval clicker, which needs a wrapped .app with Automation grants a
# human adds in System Settings (see wrap-in-app). Non-Xcode upstreams need none of
# that and run as installed here. The plist is GENERATED but not loaded; load it with:
#   launchctl bootstrap gui/$(id -u) <repo>/.astra/mcp-front/launchd.plist
#
# Usage: repo-daemon-install.sh --into <repo>
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"

REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) REPO="${2:-}"; shift 2 ;;
    *) echo "repo-daemon-install: unknown flag '$1'" >&2; exit 64 ;;
  esac
done
[ -n "$REPO" ] || { echo "usage: repo-daemon-install.sh --into <repo>" >&2; exit 64; }
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "repo-daemon-install: no such repo directory" >&2; exit 66; }

# The astra cardinal rule: never global. A per-repo daemon belongs in a repo.
case "$REPO" in
  "$HOME"|"$HOME/"|"$HOME/.claude"*|"$HOME/.agents"*|"$HOME/.config"*|"$HOME/Library"*)
    echo "repo-daemon-install: refusing target '$REPO' — per-repo means a repo, never HOME or a global config dir" >&2
    exit 64 ;;
esac
[ -d "$REPO/.git" ] || { echo "repo-daemon-install: '$REPO' is not a git repo (no .git)" >&2; exit 65; }

DEST="$REPO/.astra/mcp-front"
mkdir -p "$DEST"

clone() { # APFS clone with plain-copy fallback for non-APFS filesystems
  cp -c "$1" "$2" 2>/dev/null || cp "$1" "$2"
}
clone "$HERE/daemon.py"           "$DEST/daemon.py"
clone "$HERE/mcp_config.py"       "$DEST/mcp_config.py"
clone "$HERE/repo-daemon-run.sh"  "$DEST/run.sh"
chmod +x "$DEST/run.sh"

# The machine-owned config placeholder (mogenerator convention: the template layer
# overwrites this on every update; the sibling mcp_info.json stays human-owned). The
# placeholder is deliberately INVALID-to-serve — a daemon launched before a template
# writes real upstreams should die loudly at startup, not serve an empty surface.
if [ ! -f "$DEST/_mcp_info.json" ]; then
  printf '{"mcpServers": {}}\n' > "$DEST/_mcp_info.json"
fi

LABEL="com.jonathansaggau.astra-mcp-front.$(printf '%s' "$REPO" | cksum | cut -d' ' -f1)"
# KeepAlive is BARE true on purpose: {SuccessfulExit:false} reads a clean
# exit-on-EADDRINUSE as "finished on purpose" and the daemon silently stays dead
# (found live 2026-08-14, asserted ever since in test-xcode-mcp-front.sh).
cat > "$DEST/launchd.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$DEST/run.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$DEST/daemon.log</string>
  <key>StandardErrorPath</key><string>$DEST/daemon.log</string>
</dict>
</plist>
PLIST

echo "repo-daemon-install: installed into $DEST (label $LABEL)"
echo "  next: have the template write $DEST/_mcp_info.json, then"
echo "  launchctl bootstrap gui/\$(id -u) $DEST/launchd.plist"
exit 0
