#!/usr/bin/env bash
# install-into-repo.sh — wire Drew's agents-and-prompts components into ONE repo's agent
# config, REPO-LEVEL and non-clobbering: appends a marked managed block of @-imports to the
# repo's CLAUDE.md and AGENTS.md (creating them if absent). Never touches global configs
# (that's what Drew's own update.sh does, on HIS machine — see WARNING-drews-update-sh.md).
#   install-into-repo.sh <repo-path> [--set swift|jira|all — comma-combinable, e.g. swift,jira]  (default: swift)
#   uninstall-from-repo.sh <repo-path>   removes the block, touches nothing else
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
KIT="$(cd "$(dirname "$0")/../../agents-and-prompts" && pwd)"
REPO="${1:?usage: install-into-repo.sh <repo-path> [--set swift|jira|all]}"; shift || true
SET="swift"; [ "${1:-}" = "--set" ] && SET="$2"
BEGIN="# >>> drew-kit imports (managed by drew-kit/install-into-repo.sh) >>>"
END="# <<< drew-kit imports <<<"
FILES=()
for part in $(echo "$SET" | tr ',' ' '); do
  case "$part" in
    swift) FILES+=(SwiftCodeStyle.md SwiftAsyncAwaitConcurrency.md SwiftCodeCorrectnessAndSafety.md SwiftUIRules.md SwiftMisc.md BuildingAppleProjects.md) ;;
    jira)  FILES+=(AtlassianJira.md) ;;
    all)   FILES+=($(cd "$KIT/components" && ls *.md | grep -vE 'UserPersona|END_OF_RESPONSE')) ;;
    *) echo "unknown set: $part (swift|jira|all, comma-combinable)"; exit 1 ;;
  esac
done
for target in "$REPO/CLAUDE.md" "$REPO/AGENTS.md"; do
  touch "$target"
  if grep -qF "$BEGIN" "$target"; then
    # refresh: strip old block first (guarded like pdf-sidecars)
    bs=$(grep -nF "$BEGIN" "$target" | head -1 | cut -d: -f1); be=$(grep -nF "$END" "$target" | head -1 | cut -d: -f1)
    { [ -n "$bs" ] && [ -n "$be" ] && [ "$be" -gt "$bs" ]; } || { echo "markers broken in $target — fix by hand"; exit 1; }
    { head -n $((bs-1)) "$target"; tail -n +$((be+1)) "$target"; } > "$target.tmp" && mv "$target.tmp" "$target"
  fi
  { echo ""; echo "$BEGIN"; echo "Drew's shared components (read each):"; echo ""
    for f in "${FILES[@]}"; do echo "@$KIT/components/$f"; done
    echo "$END"; } >> "$target"
  echo "wired $SET set into $target"
done
