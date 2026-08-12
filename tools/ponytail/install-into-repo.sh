#!/usr/bin/env bash
# install-into-repo.sh — put the ponytail skill (DietrichGebert/ponytail: "the laziest senior
# dev" decision ladder — does this need to exist? stdlib? platform? existing dep? one line?)
# into ONE repo's .claude/skills/, repo-level. Which-first: skips if already present.
#   install-into-repo.sh <repo-path>     ·  uninstall: rm -rf <repo>/.claude/skills/ponytail
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
REPO="${1:?usage: install-into-repo.sh <repo-path>}"
DEST="$REPO/.claude/skills/ponytail"
[ -f "$DEST/SKILL.md" ] && { echo "already installed: $DEST"; exit 0; }
mkdir -p "$DEST"
curl -fsSL "https://raw.githubusercontent.com/DietrichGebert/ponytail/main/SKILL.md" -o "$DEST/SKILL.md"
grep -q "name:" "$DEST/SKILL.md" && echo "installed: $DEST/SKILL.md" || { echo "download looks wrong — inspect $DEST/SKILL.md"; exit 1; }
