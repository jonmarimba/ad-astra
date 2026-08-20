#!/bin/bash
# xcode-mcp-front-run.sh — the actual process launchd supervises (NOT meant to be
# run by hand; use `xcode-mcp-front launchd-install` to wire this up).
#
# Just execs daemon.py. Used to also run a one-shot bash-side "click Allow if
# present" poll here — moved INTO daemon.py's own connection_manager loop
# instead (2026-08-14), because a fixed one-shot window at spawn and the
# Python-side reconnect loop weren't on the same timer: the click could miss
# its window and the daemon would sit there stuck with nothing left trying to
# unblock it. Now the same loop that decides "try to reconnect" also decides
# "try to click Allow first" — one clock, not two racing ones.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${XCODE_MCP_FRONT_PORT:-8765}"

# shellcheck disable=SC1091
. "$HERE/self-preempt.sh"

exec uv run --script "$HERE/daemon.py"
