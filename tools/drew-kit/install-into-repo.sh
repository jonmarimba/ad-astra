#!/usr/bin/env bash
# install-into-repo.sh — wire Drew's agents-and-prompts components into ONE repo, SELF-CONTAINED
# and portable: it COPIES the chosen component files into <repo>/.drew-kit/components/ and appends
# a marked block of REPO-RELATIVE @-imports to the repo's CLAUDE.md and AGENTS.md. So the repo
# carries its own copy — clone it anywhere, on any machine, and the imports still resolve.
# (An earlier version wrote ABSOLUTE @/Users/.../js-db-ad-astra/... paths, which dangle the moment
# the repo moves or is cloned elsewhere. That was the bug this fixes.)
#
#   install-into-repo.sh <repo-path> [--set swift|jira|all — comma-combinable, e.g. swift,jira]  (default: swift)
#   uninstall-from-repo.sh <repo-path>   removes the block AND the copied .drew-kit/, touches nothing else
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
KIT="$(cd "$(dirname "$0")/../../agents-and-prompts" && pwd)"
REPO="${1:?usage: install-into-repo.sh <repo-path> [--set swift|jira|all]}"; shift || true
SET="swift"; [ "${1:-}" = "--set" ] && SET="$2"
[ -d "$REPO" ] || { echo "no such repo: $REPO" >&2; exit 1; }
BEGIN="# >>> drew-kit imports (managed by drew-kit/install-into-repo.sh) >>>"
END="# <<< drew-kit imports <<<"
DEST=".drew-kit/components"   # repo-relative — the copy lives IN the repo

FILES=()
for part in $(echo "$SET" | tr ',' ' '); do
  case "$part" in
    swift) FILES+=(SwiftCodeStyle.md SwiftAsyncAwaitConcurrency.md SwiftCodeCorrectnessAndSafety.md SwiftUIRules.md SwiftMisc.md BuildingAppleProjects.md) ;;
    jira)  FILES+=(AtlassianJira.md) ;;
    all)   FILES+=($(cd "$KIT/components" && ls *.md | grep -vE 'UserPersona|END_OF_RESPONSE')) ;;
    *) echo "unknown set: $part (swift|jira|all, comma-combinable)"; exit 1 ;;
  esac
done

# copy the selected components INTO the repo (fresh each run so a --set change doesn't leave orphans)
rm -rf "$REPO/$DEST"; mkdir -p "$REPO/$DEST"
for f in "${FILES[@]}"; do
  [ -f "$KIT/components/$f" ] || { echo "missing source component: $f" >&2; exit 1; }
  cp "$KIT/components/$f" "$REPO/$DEST/$f"
done

for target in "$REPO/CLAUDE.md" "$REPO/AGENTS.md"; do
  touch "$target"
  if grep -qF "$BEGIN" "$target"; then
    # refresh: strip old block first (guarded — a broken/misordered marker aborts, never mangles)
    bs=$(grep -nF "$BEGIN" "$target" | head -1 | cut -d: -f1); be=$(grep -nF "$END" "$target" | head -1 | cut -d: -f1)
    { [ -n "$bs" ] && [ -n "$be" ] && [ "$be" -gt "$bs" ]; } || { echo "markers broken in $target — fix by hand"; exit 1; }
    { head -n $((bs-1)) "$target"; tail -n +$((be+1)) "$target"; } > "$target.tmp" && mv "$target.tmp" "$target"
  fi
  { echo ""; echo "$BEGIN"; echo "Drew's shared components (repo-local copy under $DEST/; read each):"; echo ""
    for f in "${FILES[@]}"; do echo "@$DEST/$f"; done
    echo "$END"; } >> "$target"
  echo "wired $SET set into $target (repo-relative @$DEST/…)"
done
echo "copied $(echo "${FILES[@]}" | wc -w | tr -d ' ') component(s) into $REPO/$DEST"
