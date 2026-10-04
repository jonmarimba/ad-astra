#!/usr/bin/env bash
# vendor.sh — refresh astra's tracked copy of upstream blader/humanizer (MIT).
# Installers only ever copy the tracked files; fetching happens here, on purpose,
# so every repo gets the same reviewed version and the update hook can track it.
set -euo pipefail
D="$(cd "$(dirname "$0")/../../agents-and-prompts/skills/humanizer/upstream" && pwd)"
SHA="$(curl -fsSL https://api.github.com/repos/blader/humanizer/commits/main | python3 -c 'import json,sys;print(json.load(sys.stdin)["sha"])')"
for f in SKILL.md LICENSE; do curl -fsSL "https://raw.githubusercontent.com/blader/humanizer/$SHA/$f" -o "$D/$f"; done
printf 'Vendored from https://github.com/blader/humanizer at %s (MIT, see LICENSE).\nRefresh with tools/humanizer/vendor.sh; the installer copies these files, it never fetches.\n' "$SHA" > "$D/SOURCE"
echo "humanizer upstream now at $SHA. Review the diff, commit, and every repo picks it up on its next commit."
