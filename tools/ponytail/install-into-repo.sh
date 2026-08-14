#!/usr/bin/env bash
# install-into-repo.sh — put the ponytail skill (DietrichGebert/ponytail: "the laziest senior
# dev" decision ladder — does this need to exist? stdlib? platform? existing dep? one line?)
# into ONE repo's .claude/skills/, repo-level. Which-first: skips if already present.
#   install-into-repo.sh <repo-path>     ·  uninstall: rm -rf <repo>/.claude/skills/ponytail
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
REPO="${1:?usage: install-into-repo.sh <repo-path>}"
[ -d "$REPO" ] || { echo "install-into-repo.sh: no such directory: $REPO" >&2; exit 1; }
BASE="https://raw.githubusercontent.com/DietrichGebert/ponytail/main/skills"
for skill in ponytail ponytail-audit; do
  DEST="$REPO/.claude/skills/$skill"
  if [ -f "$DEST/SKILL.md" ]; then echo "already installed: $DEST"; continue; fi
  mkdir -p "$DEST"
  curl -fsSL "$BASE/$skill/SKILL.md" -o "$DEST/SKILL.md"
  grep -q "name:" "$DEST/SKILL.md" && echo "installed: $DEST/SKILL.md" || { echo "download looks wrong — inspect $DEST/SKILL.md"; exit 1; }
done
