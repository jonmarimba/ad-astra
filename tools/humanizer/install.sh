#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the humanizer skill: upstream's SKILL.md (vendored, MIT) plus Jonathan's voice calibration, placed into <repo>/.claude/skills/ and recorded.
# Generated on the shared pattern (2026-10-04): every per-repo tool installs
# through astra_place/astra_place_at and uninstalls through astra_remove, so
# its files are tracked in .astra/manifest.json, updated by the post-commit
# hook, and gone for good once uninstalled.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
# Retire the old install, which fetched upstream at install time with
# `npx skills add` into .agents/skills/ behind a symlink and was never tracked.
if [ -f "$TARGET/skills-lock.json" ] && grep -q '"blader/humanizer"' "$TARGET/skills-lock.json"; then
  rm -rf "$TARGET/.agents/skills/humanizer"
  rmdir "$TARGET/.agents/skills" "$TARGET/.agents" 2>/dev/null || true
  python3 - "$TARGET/skills-lock.json" <<'PY2'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d.get("skills", {}).pop("humanizer", None)
if d.get("skills"):
    p.write_text(json.dumps(d, indent=2) + "\n")
else:
    p.unlink()
PY2
fi
[ -L "$TARGET/.claude/skills/humanizer" ] && rm "$TARGET/.claude/skills/humanizer"
astra_place_at humanizer \
  "agents-and-prompts/skills/humanizer/upstream/SKILL.md:.claude/skills/humanizer/SKILL.md" \
  "agents-and-prompts/skills/humanizer/SKILL.md:.claude/skills/humanizer/voice-calibration.md" \
  "agents-and-prompts/skills/humanizer/upstream/LICENSE:.claude/skills/humanizer/LICENSE"
