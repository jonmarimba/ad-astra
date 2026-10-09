#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the adhd skill, placed into <repo>/.claude/skills/ and recorded in .astra/manifest.json.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_place_at adhd \
  "agents-and-prompts/skills/adhd/SKILL.md:.claude/skills/adhd/SKILL.md"
