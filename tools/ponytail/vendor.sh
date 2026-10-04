#!/usr/bin/env bash
# vendor.sh — refresh astra's tracked copy of upstream DietrichGebert/ponytail (MIT).
# Installers only ever copy the tracked files; fetching happens here, on purpose.
set -euo pipefail
D="$(cd "$(dirname "$0")/../../agents-and-prompts/skills/ponytail" && pwd)"
SHA="$(curl -fsSL https://api.github.com/repos/DietrichGebert/ponytail/commits/main | python3 -c 'import json,sys;print(json.load(sys.stdin)["sha"])')"
for s in ponytail ponytail-audit; do curl -fsSL "https://raw.githubusercontent.com/DietrichGebert/ponytail/$SHA/skills/$s/SKILL.md" -o "$D/$s/SKILL.md"; done
curl -fsSL "https://raw.githubusercontent.com/DietrichGebert/ponytail/$SHA/LICENSE" -o "$D/LICENSE"
printf 'Vendored from https://github.com/DietrichGebert/ponytail at %s (MIT, see LICENSE).\nRefresh with tools/ponytail/vendor.sh; the installer copies these files, it never fetches.\n' "$SHA" > "$D/SOURCE"
echo "ponytail upstream now at $SHA. Review the diff, commit, and every repo picks it up on its next commit."
