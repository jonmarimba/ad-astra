#!/usr/bin/env bash
# install.sh — full setup: deps, the TCC-grantable app wrapper, and the launchd
# job that keeps xcode-mcp-front running across logins (RunAtLoad, KeepAlive).
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"

command -v uv >/dev/null || { echo "uv not found — install via 'brew install uv'" >&2; exit 1; }
mkdir -p "$HOME/.xcode-mcp-front"

APP="$HERE/XcodeMCPFront.app"
if [ ! -e "$APP" ]; then
  echo "wrapping xcode-mcp-front-run.sh in an app (TCC needs a stable identity to grant Accessibility/Automation to)"
  "$HERE/../wrap-in-app/wrap-in-app" "$HERE/xcode-mcp-front-run.sh" \
    --log "$HOME/.xcode-mcp-front/daemon.log" --name XcodeMCPFront --outdir "$HERE"
else
  echo "XcodeMCPFront.app already exists — leaving it alone (re-wrapping would kill any TCC grant it holds)"
fi

"$HERE/xcode-mcp-front" launchd-install

cat <<'EOF'

First run: macOS will prompt to let XcodeMCPFront control "System Events" —
that's Accessibility/Automation access, needed for the auto-click-Allow
behavior (default on). Grant it once; the .app's identity is stable across
script edits, so this shouldn't need re-granting unless the .app itself is
edited or re-wrapped.

Auto-allow defaults ON. To require a manual click instead:
  XCODE_MCP_FRONT_AUTO_ALLOW=0 ./xcode-mcp-front launchd-install

Check status any time:  ./xcode-mcp-front launchd-status
Tail the log:           ./xcode-mcp-front logs
EOF
