#!/usr/bin/env bash
# deps.sh — refresh the software this tool's repo entry points at: the MacControlMCP app. `astra upgrade`
# runs it; install.sh runs the same step. It downloads the latest signed release and checks its sha256.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/fetch-app.sh"
