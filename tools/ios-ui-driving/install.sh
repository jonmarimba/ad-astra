#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the ios-ui-driving skill, placed into <repo>/.claude/skills/ and recorded.
# Generated on the shared pattern (2026-10-04): every per-repo tool installs
# through astra_place/astra_place_at and uninstalls through astra_remove, so
# its files are tracked in .astra/manifest.json, updated by the post-commit
# hook, and gone for good once uninstalled.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_place_at ios-ui-driving \
  "agents-and-prompts/skills/ios-ui-driving/SKILL.md:.claude/skills/ios-ui-driving/SKILL.md"
