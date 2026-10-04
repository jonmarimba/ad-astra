#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the ponytail and ponytail-audit skills (vendored from upstream, MIT), placed into <repo>/.claude/skills/ and recorded.
# Generated on the shared pattern (2026-10-04): every per-repo tool installs
# through astra_place/astra_place_at and uninstalls through astra_remove, so
# its files are tracked in .astra/manifest.json, updated by the post-commit
# hook, and gone for good once uninstalled.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
# Earlier installs curl'd these from GitHub untracked; remove them so the
# tracked copies below replace them cleanly.
rm -f "$TARGET/.claude/skills/ponytail/SKILL.md" "$TARGET/.claude/skills/ponytail-audit/SKILL.md"
astra_place_at ponytail \
  "agents-and-prompts/skills/ponytail/ponytail/SKILL.md:.claude/skills/ponytail/SKILL.md" \
  "agents-and-prompts/skills/ponytail/ponytail-audit/SKILL.md:.claude/skills/ponytail-audit/SKILL.md" \
  "agents-and-prompts/skills/ponytail/LICENSE:.claude/skills/ponytail/LICENSE"
