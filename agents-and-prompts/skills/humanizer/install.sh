#!/usr/bin/env bash
# install.sh — install the humanizer skill into a target repo.
#
# Installs TWO things:
#   1. The upstream blader/humanizer skill (35 AI-tell patterns from Wikipedia).
#      Pulled fresh from the external source every time — not a snapshot.
#   2. Our voice-calibration layer (this directory's SKILL.md → voice-calibration.md
#      in the target, so it doesn't collide with the upstream's own SKILL.md).
#
# Re-run anytime to pull upstream updates.
#
#   install.sh <repo>
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${1:-}"
[ -n "$REPO" ] || { echo "usage: install.sh <repo>" >&2; exit 64; }
[ -d "$REPO" ] || { echo "no such repo: $REPO" >&2; exit 1; }
REPO="$(cd "$REPO" && pwd)"

echo "Installing humanizer into $REPO"

# Step 1: upstream from external source, per-repo (not --global)
cd "$REPO"
npx skills add blader/humanizer

# Step 2: our voice-calibration layer alongside the upstream
SKILL_DIR="$REPO/.claude/skills/humanizer"
if [ ! -d "$SKILL_DIR" ]; then
    echo "ERROR: upstream install didn't create $SKILL_DIR" >&2
    exit 1
fi
cp "$SCRIPT_DIR/SKILL.md" "$SKILL_DIR/voice-calibration.md"

echo "Done. Upstream (35 AI-tell patterns) + voice calibration installed at $SKILL_DIR"
