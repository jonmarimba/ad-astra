#!/usr/bin/env bash
set -euo pipefail
REPO="${1:?usage: uninstall-from-repo.sh <repo-path>}"
BEGIN="# >>> drew-kit imports (managed by drew-kit/install-into-repo.sh) >>>"
END="# <<< drew-kit imports <<<"
for target in "$REPO/CLAUDE.md" "$REPO/AGENTS.md"; do
  [ -f "$target" ] || continue
  grep -qF "$BEGIN" "$target" || continue
  bs=$(grep -nF "$BEGIN" "$target" | head -1 | cut -d: -f1); be=$(grep -nF "$END" "$target" | head -1 | cut -d: -f1)
  { [ -n "$bs" ] && [ -n "$be" ] && [ "$be" -gt "$bs" ]; } || { echo "markers broken in $target"; exit 1; }
  { head -n $((bs-1)) "$target"; tail -n +$((be+1)) "$target"; } > "$target.tmp" && mv "$target.tmp" "$target"
  echo "removed drew-kit block from $target"
done
