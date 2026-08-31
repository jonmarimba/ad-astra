#!/usr/bin/env bash
# install-into-repo.sh — wire Drew's agents-and-prompts components into ONE repo, portably, by a
# chosen METHOD. All three write a marked block of REPO-RELATIVE @-imports to CLAUDE.md/AGENTS.md
# (never absolute machine paths). They differ only in HOW the component files get into the repo:
#
#   --method copy       (default) copy the selected components into <repo>/.drew-kit/components/.
#                       Self-contained + portable; the tradeoff is it can DRIFT from Drew's source.
#   --method submodule  git submodule add <--src repo> at <repo>/.drew-kit-src ; single source of
#                       truth, versioned (bump the pointer to update). Needs --src.
#   --method subtree    git subtree add --prefix .drew-kit-src <--src repo> ; the WHOLE src repo's
#                       files are committed into the repo (self-contained) but keep upstream lineage
#                       (git subtree pull to update). Needs --src.
#   --method subtree-split  carve ONLY --split-prefix out of --src's history (git subtree split),
#                       then subtree-add/pull just that piece into .drew-kit-src/. Self-contained,
#                       updatable, and "just the stuff we need" — no whole-repo drag, no separate
#                       components repo to stand up. Defaults --src to your local ad-astra checkout
#                       and --split-prefix to agents-and-prompts/components, so plain
#                       `--method subtree-split` Just Works. This is the one to use for drew-kit.
#
# install == update: for the subtree methods, the FIRST run does `subtree add`, later runs do
# `subtree pull` — same command, the script detects which. Re-run to update; there is no separate
# update command.
#
# WHY the methods exist: an earlier version wrote ABSOLUTE @/Users/.../js-db-ad-astra/... imports —
# they dangle on clone/move. plain submodule/subtree are only "clean" when the components are their
# OWN repo; today they're a subfolder of ad-astra, so pointing --src at all of ad-astra drags the
# whole repo — which is exactly what subtree-split fixes (it extracts just the subdir's history).
#
#   install-into-repo.sh <repo> [--set swift|jira|all] [--method copy|submodule|subtree|subtree-split]
#                               [--src <git-url|path>] [--branch <b>] [--subpath <dir-in-src>]
#                               [--split-prefix <dir-in-src>]
#   uninstall-from-repo.sh <repo>   removes the block + whatever the method installed
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
KIT="$(cd "$(dirname "$0")/../../agents-and-prompts" && pwd)"

REPO=""; SET="swift"; METHOD="copy"; SRC=""; BRANCH="main"; SUBPATH="agents-and-prompts/components"; SPLIT_PREFIX=""
while [ $# -gt 0 ]; do case "$1" in
  --set) SET="$2"; shift 2;;
  --method) METHOD="$2"; shift 2;;
  --src) SRC="$2"; shift 2;;
  --branch) BRANCH="$2"; shift 2;;
  --subpath) SUBPATH="$2"; shift 2;;
  --split-prefix) SPLIT_PREFIX="$2"; shift 2;;
  --*) echo "unknown flag '$1'" >&2; exit 64;;
  *) [ -z "$REPO" ] && REPO="$1" || { echo "one repo path only" >&2; exit 64; }; shift;;
esac; done
[ -n "$REPO" ] || { echo "usage: install-into-repo.sh <repo> [--set …] [--method copy|submodule|subtree|subtree-split] [--src url|path] [--branch b] [--subpath dir] [--split-prefix dir]" >&2; exit 64; }
[ -d "$REPO" ] || { echo "no such repo: $REPO" >&2; exit 1; }
case "$METHOD" in copy|submodule|subtree|subtree-split) ;; *) echo "unknown --method '$METHOD' (copy|submodule|subtree|subtree-split)" >&2; exit 64;; esac

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

# git methods commit as they go and git subtree/submodule REFUSE on a dirty tree — fail early and
# clearly instead of dying mid-operation with git's cryptic "working tree has modifications".
case "$METHOD" in
  submodule|subtree|subtree-split)
    git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "$METHOD needs $REPO to be a git repo" >&2; exit 1; }
    { git -C "$REPO" diff --quiet && git -C "$REPO" diff --cached --quiet; } || {
      echo "$METHOD needs a CLEAN working tree in $REPO — git subtree/submodule refuse otherwise. Commit or stash first (copy method has no such requirement)." >&2; exit 1; }
    ;;
esac

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
  subtree-split)
    # source + subdir default to the local ad-astra checkout's components, so plain
    # `--method subtree-split` needs no other flags.
    SRC="${SRC:-$(git -C "$KIT" rev-parse --show-toplevel)}"
    [ -z "$SPLIT_PREFIX" ] && SPLIT_PREFIX="agents-and-prompts/components"
    git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "subtree-split needs $REPO to be a git repo" >&2; exit 1; }
    git -C "$SRC"  rev-parse --git-dir >/dev/null 2>&1 || { echo "subtree-split needs --src ($SRC) to be a git repo" >&2; exit 1; }
    git -C "$SRC" cat-file -e "HEAD:$SPLIT_PREFIX" 2>/dev/null || { echo "--split-prefix '$SPLIT_PREFIX' not found in $SRC's HEAD" >&2; exit 1; }
    # carve ONLY that subdir out of the source's committed history into a transient synthetic branch
    git -C "$SRC" branch -D drew-kit-split >/dev/null 2>&1 || true
    git -C "$SRC" subtree split --prefix="$SPLIT_PREFIX" -b drew-kit-split >/dev/null
    # add first time, pull to update (install == update); --squash keeps one commit per update
    if [ -d "$REPO/.drew-kit-src" ]; then git -C "$REPO" subtree pull --prefix .drew-kit-src "$SRC" drew-kit-split --squash -m "drew-kit: update Drew's components (subtree pull)";
    else git -C "$REPO" subtree add --prefix .drew-kit-src "$SRC" drew-kit-split --squash; fi
    git -C "$SRC" branch -D drew-kit-split >/dev/null 2>&1 || true   # transient — don't litter the source repo
    IMPORT_DIR=".drew-kit-src"   # split makes the components the ROOT of the subtree
    ;;
esac
# submodule/subtree: warn if the selected components aren't actually at the subpath (wrong --subpath)
if [ "$METHOD" != copy ]; then
  for f in "${FILES[@]}"; do [ -f "$REPO/$IMPORT_DIR/$f" ] || echo "warning: $IMPORT_DIR/$f not found in the source — check --subpath" >&2; done
fi

for target in "$REPO/CLAUDE.md" "$REPO/AGENTS.md"; do
  touch "$target"
  if grep -qF "$BEGIN" "$target"; then
    # `|| true` because a missing END marker makes the grep pipeline exit 1, and under
    # `set -euo pipefail` a failing command substitution in a plain assignment kills the
    # script BEFORE the broken-markers message below can print. The abort was correct but
    # silent; the guard on the next line is where the refusal is supposed to speak.
    bs=$(grep -nF "$BEGIN" "$target" | head -1 | cut -d: -f1 || true); be=$(grep -nF "$END" "$target" | head -1 | cut -d: -f1 || true)
    { [ -n "$bs" ] && [ -n "$be" ] && [ "$be" -gt "$bs" ]; } || { echo "markers broken in $target — fix by hand" >&2; exit 1; }
    { head -n $((bs-1)) "$target"; tail -n +$((be+1)) "$target"; } > "$target.tmp" && mv "$target.tmp" "$target"
  fi
  { echo ""; echo "$BEGIN"; echo "Drew's shared components ($METHOD @ $IMPORT_DIR/; read each):"; echo ""
    for f in "${FILES[@]}"; do echo "@$IMPORT_DIR/$f"; done
    echo "$END"; } >> "$target"
  echo "wired $SET into $target ($METHOD, @$IMPORT_DIR/…)"
done

# The subtree/submodule methods commit as they go (subtree add/pull make merges; submodule stages a
# gitlink), so the import block MUST be committed too or the tree stays dirty and the next run's
# subtree op aborts ("working tree has modifications"). Stage ONLY drew-kit's own paths so an
# install never sweeps unrelated work-in-progress into a commit. copy leaves everything for the
# user to commit, as before.
case "$METHOD" in
  submodule|subtree|subtree-split)
    stage=()
    for p in CLAUDE.md AGENTS.md .gitmodules .drew-kit-src .drew-kit; do [ -e "$REPO/$p" ] && stage+=("$p"); done
    [ ${#stage[@]} -gt 0 ] && git -C "$REPO" add -- "${stage[@]}"
    git -C "$REPO" diff --cached --quiet || git -C "$REPO" commit -q -m "drew-kit: wire Drew's components ($METHOD, $SET)"
    ;;
esac
