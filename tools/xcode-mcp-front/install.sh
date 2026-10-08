#!/usr/bin/env bash
# astra-scope: machine
# install.sh — full setup: deps, the TCC-grantable app wrapper, and the launchd
# job that keeps xcode-mcp-front running across logins (RunAtLoad, KeepAlive).
set -euo pipefail
export PATH="${ASTRA_PATH:-/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH}"
HERE="$(cd "$(dirname "$0")" && pwd)"

command -v uv >/dev/null || { echo "uv not found — install via 'brew install uv'" >&2; exit 1; }
mkdir -p "$HOME/.xcode-mcp-front"

# The wrapper apps are generated per machine and never committed: each points
# at this checkout's script by absolute path, and its TCC grant is tied to its
# exact bytes, so a committed app only works on the Mac that built it. Build any
# that are missing; never rebuild one that exists (that would kill its grant).
for spec in "XcodeMCPFront:xcode-mcp-front-run.sh:.xcode-mcp-front" \
            "XcodeCombinedFront:xcode-combined-front-run.sh:.xcode-combined-front" \
            "Xcode27CombinedFront:xcode27-combined-front-run.sh:.xcode27-combined-front"; do
  name="${spec%%:*}"; rest="${spec#*:}"; script="${rest%%:*}"; logdir="${rest#*:}"
  mkdir -p "$HOME/$logdir"
  if [ ! -e "$HERE/$name.app" ]; then
    echo "wrapping $script in $name.app (TCC needs a stable identity to grant Accessibility/Automation to)"
    "$HERE/../wrap-in-app/wrap-in-app" "$HERE/$script" --log "$HOME/$logdir/daemon.log" --name "$name" --outdir "$HERE"
  else
    echo "$name.app already exists — leaving it alone (re-wrapping would kill any TCC grant it holds)"
  fi
done
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
