#!/usr/bin/env bash
# install-into-repo.sh — wire Drew's agents-and-prompts components into ONE repo, portably, by a
# chosen METHOD. All three write a marked block of REPO-RELATIVE @-imports to CLAUDE.md/AGENTS.md
# (never absolute machine paths). They differ only in HOW the component files get into the repo:
#
#   --method copy       (default) copy the selected components into <repo>/.drew-kit/components/.
#                       Self-contained + portable; the tradeoff is it can DRIFT from Drew's source.
#   --method submodule  git submodule add <--src repo> at <repo>/.drew-kit-src ; single source of
#                       truth, versioned (bump the pointer to update). Needs --src.
#   --method subtree    git subtree add --prefix .drew-kit-src <--src repo> ; files are committed
#                       into the repo (self-contained) but keep upstream lineage (git subtree pull
#                       to update). Needs --src.
#
# WHY the methods exist: an earlier version wrote ABSOLUTE @/Users/.../js-db-ad-astra/... imports —
# they dangle on clone/move. submodule/subtree are only "clean" when the components are their OWN
# repo; today they're a subfolder of ad-astra, so pointing --src at all of ad-astra drags the whole
# repo. Until a dedicated components repo exists, copy is the pragmatic default.
#
#   install-into-repo.sh <repo> [--set swift|jira|all] [--method copy|submodule|subtree]
#                               [--src <git-url>] [--branch <b>] [--subpath <dir-in-src>]
#   uninstall-from-repo.sh <repo>   removes the block + whatever the method installed
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
KIT="$(cd "$(dirname "$0")/../../agents-and-prompts" && pwd)"

REPO=""; SET="swift"; METHOD="copy"; SRC=""; BRANCH="main"; SUBPATH="agents-and-prompts/components"
while [ $# -gt 0 ]; do case "$1" in
  --set) SET="$2"; shift 2;;
  --method) METHOD="$2"; shift 2;;
  --src) SRC="$2"; shift 2;;
  --branch) BRANCH="$2"; shift 2;;
  --subpath) SUBPATH="$2"; shift 2;;
  --*) echo "unknown flag '$1'" >&2; exit 64;;
  *) [ -z "$REPO" ] && REPO="$1" || { echo "one repo path only" >&2; exit 64; }; shift;;
esac; done
[ -n "$REPO" ] || { echo "usage: install-into-repo.sh <repo> [--set …] [--method copy|submodule|subtree] [--src url] [--branch b] [--subpath dir]" >&2; exit 64; }
[ -d "$REPO" ] || { echo "no such repo: $REPO" >&2; exit 1; }
case "$METHOD" in copy|submodule|subtree) ;; *) echo "unknown --method '$METHOD' (copy|submodule|subtree)" >&2; exit 64;; esac

BEGIN="# >>> drew-kit imports (managed by drew-kit/install-into-repo.sh) >>>"
END="# <<< drew-kit imports <<<"

FILES=()
for part in $(echo "$SET" | tr ',' ' '); do
  case "$part" in
    swift) FILES+=(SwiftCodeStyle.md SwiftAsyncAwaitConcurrency.md SwiftCodeCorrectnessAndSafety.md SwiftUIRules.md SwiftMisc.md BuildingAppleProjects.md) ;;
    jira)  FILES+=(AtlassianJira.md) ;;
    all)   FILES+=($(cd "$KIT/components" && ls *.md | grep -vE 'UserPersona|END_OF_RESPONSE')) ;;
    *) echo "unknown set: $part (swift|jira|all, comma-combinable)" >&2; exit 1 ;;
  esac
done

# place the component files by method; set IMPORT_DIR to the repo-relative dir the @-imports use.
case "$METHOD" in
  copy)
    IMPORT_DIR=".drew-kit/components"
    rm -rf "$REPO/$IMPORT_DIR"; mkdir -p "$REPO/$IMPORT_DIR"
    for f in "${FILES[@]}"; do
      [ -f "$KIT/components/$f" ] || { echo "missing source component: $f" >&2; exit 1; }
      cp "$KIT/components/$f" "$REPO/$IMPORT_DIR/$f"
    done
    ;;
  submodule)
    [ -n "$SRC" ] || { echo "--method submodule needs --src <git-url> (the repo hosting the components)" >&2; exit 64; }
    git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "submodule needs $REPO to be a git repo" >&2; exit 1; }
    [ -e "$REPO/.drew-kit-src" ] || git -C "$REPO" submodule add -b "$BRANCH" "$SRC" .drew-kit-src
    git -C "$REPO" submodule update --init .drew-kit-src
    IMPORT_DIR=".drew-kit-src/$SUBPATH"
    ;;
  subtree)
    [ -n "$SRC" ] || { echo "--method subtree needs --src <git-url>" >&2; exit 64; }
    git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "subtree needs $REPO to be a git repo" >&2; exit 1; }
    if [ -d "$REPO/.drew-kit-src" ]; then git -C "$REPO" subtree pull --prefix .drew-kit-src "$SRC" "$BRANCH" --squash -m "drew-kit: subtree pull";
    else git -C "$REPO" subtree add --prefix .drew-kit-src "$SRC" "$BRANCH" --squash; fi
    IMPORT_DIR=".drew-kit-src/$SUBPATH"
    ;;
esac
# submodule/subtree: warn if the selected components aren't actually at the subpath (wrong --subpath)
if [ "$METHOD" != copy ]; then
  for f in "${FILES[@]}"; do [ -f "$REPO/$IMPORT_DIR/$f" ] || echo "warning: $IMPORT_DIR/$f not found in the source — check --subpath" >&2; done
fi

for target in "$REPO/CLAUDE.md" "$REPO/AGENTS.md"; do
  touch "$target"
  if grep -qF "$BEGIN" "$target"; then
    bs=$(grep -nF "$BEGIN" "$target" | head -1 | cut -d: -f1); be=$(grep -nF "$END" "$target" | head -1 | cut -d: -f1)
    { [ -n "$bs" ] && [ -n "$be" ] && [ "$be" -gt "$bs" ]; } || { echo "markers broken in $target — fix by hand" >&2; exit 1; }
    { head -n $((bs-1)) "$target"; tail -n +$((be+1)) "$target"; } > "$target.tmp" && mv "$target.tmp" "$target"
  fi
  { echo ""; echo "$BEGIN"; echo "Drew's shared components ($METHOD @ $IMPORT_DIR/; read each):"; echo ""
    for f in "${FILES[@]}"; do echo "@$IMPORT_DIR/$f"; done
    echo "$END"; } >> "$target"
  echo "wired $SET into $target ($METHOD, @$IMPORT_DIR/…)"
done
