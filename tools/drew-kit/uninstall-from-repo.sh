#!/usr/bin/env bash
# uninstall-from-repo.sh — remove the drew-kit managed block from CLAUDE.md/AGENTS.md AND whatever
# the install method dropped in: .drew-kit/ (copy) or .drew-kit-src/ (submodule/subtree). Touches
# nothing else.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
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

# copy method
[ -d "$REPO/.drew-kit" ] && { rm -rf "$REPO/.drew-kit"; echo "removed $REPO/.drew-kit"; } || true

# submodule/subtree method: .drew-kit-src. A submodule needs deinit + .gitmodules cleanup; a subtree
# is just committed files. Detect a submodule by its presence in .gitmodules.
if [ -e "$REPO/.drew-kit-src" ]; then
  if [ -f "$REPO/.gitmodules" ] && grep -qF '.drew-kit-src' "$REPO/.gitmodules"; then
    git -C "$REPO" submodule deinit -f .drew-kit-src >/dev/null 2>&1 || true
    git -C "$REPO" rm -f .drew-kit-src >/dev/null 2>&1 || rm -rf "$REPO/.drew-kit-src"
    rm -rf "$REPO/.git/modules/.drew-kit-src"
    echo "removed submodule $REPO/.drew-kit-src"
  else
    rm -rf "$REPO/.drew-kit-src"
    echo "removed subtree $REPO/.drew-kit-src (commit the removal)"
  fi
fi
