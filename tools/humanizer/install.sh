#!/usr/bin/env bash
# humanizer — install the humanizer skill (upstream blader/humanizer 35-pattern AI-tell
# detection, pulled fresh, + our voice-calibration layer) into a repo. Thin --into wrapper
# over agents-and-prompts/skills/humanizer/install.sh, which owns the logic.
# Usage: ./install.sh --into <repo>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
while [ $# -gt 0 ]; do case "$1" in --into) TARGET="${2:-}"; shift 2;; *) echo "humanizer: unknown argument: $1" >&2; exit 64;; esac; done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
exec "$HERE/../../agents-and-prompts/skills/humanizer/install.sh" "$TARGET"
