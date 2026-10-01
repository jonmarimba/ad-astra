#!/usr/bin/env bash
# test-drew-kit.sh — install-into-repo wires the marked block into a real repo's CLAUDE.md and
# AGENTS.md without touching anything else; refresh is idempotent; uninstall removes only the
# block; broken markers abort instead of mangling the file.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
INSTALL="$HERE/../drew-kit/install-into-repo.sh"
UNINSTALL="$HERE/../drew-kit/uninstall-from-repo.sh"

REPO="$SB/repo"; mkdir -p "$REPO"
printf '# My project\nPre-existing prose that must survive.\n' > "$REPO/CLAUDE.md"

# ---- install (default swift set) ----
assert_rc 0 "install succeeds" "$INSTALL" "$REPO"
assert_contains "$REPO/CLAUDE.md" ">>> drew-kit imports" "begin marker present in CLAUDE.md"
assert_contains "$REPO/CLAUDE.md" "SwiftCodeStyle.md" "swift component imported"
assert_contains "$REPO/CLAUDE.md" "Pre-existing prose that must survive." "pre-existing content untouched"
assert_file "$REPO/AGENTS.md" "AGENTS.md created"
assert_contains "$REPO/AGENTS.md" ">>> drew-kit imports" "begin marker present in AGENTS.md"
# ---- self-contained + portable: imports are REPO-RELATIVE and components are copied IN ----
assert_contains "$REPO/CLAUDE.md" "@.drew-kit/components/SwiftCodeStyle.md" "import is repo-relative (@.drew-kit/…)"
assert_not_contains "$REPO/CLAUDE.md" "/Users/" "NO absolute machine path leaked into the import"
assert_not_contains "$REPO/CLAUDE.md" "js-db-ad-astra" "NO cross-repo absolute reference leaked in"
assert_file "$REPO/.drew-kit/components/SwiftCodeStyle.md" "component file actually copied into the repo"
[ -s "$REPO/.drew-kit/components/SwiftCodeStyle.md" ] && pass "copied component is non-empty" || fail "copied component is empty"

# ---- refresh idempotence: reinstall must not duplicate the block ----
"$INSTALL" "$REPO" >/dev/null
n="$(grep -cF '>>> drew-kit imports' "$REPO/CLAUDE.md")"
assert_eq "1" "$n" "reinstall left exactly one managed block (refresh, not append)"

# ---- set switching on refresh ----
"$INSTALL" "$REPO" --set jira >/dev/null
assert_contains "$REPO/CLAUDE.md" "AtlassianJira.md" "jira set present after --set jira refresh"
assert_not_contains "$REPO/CLAUDE.md" "SwiftCodeStyle.md" "swift set removed by the refresh"

# ---- uninstall: block gone, copied components gone, everything else intact ----
assert_rc 0 "uninstall succeeds" "$UNINSTALL" "$REPO"
assert_not_contains "$REPO/CLAUDE.md" "drew-kit imports" "managed block removed"
assert_contains "$REPO/CLAUDE.md" "Pre-existing prose that must survive." "pre-existing content still intact after uninstall"
assert_no_file "$REPO/.drew-kit/components/AtlassianJira.md" "uninstall removed the copied-in components (.drew-kit gone)"

# ---- method guards ----
red "unknown --method must fail" 64 "unknown --method 'carrier-pigeon'" "$INSTALL" "$REPO" --method carrier-pigeon
# the --src checks live PAST the "must be a git repo" guard (install-into-repo.sh:69 fires first
# for any non-copy method), so REPO must already be a clean git repo or these prove the wrong thing
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.email=t@t -c user.name=t add -A
git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm init
red "submodule without --src must fail" 64 "--method submodule needs --src" "$INSTALL" "$REPO" --method submodule
red "subtree without --src must fail" 64 "--method subtree needs --src" "$INSTALL" "$REPO" --method subtree

# ---- subtree method against a REAL local source repo (proves the method, not just the guard) ----
need git "install Xcode command-line tools: xcode-select --install"
  SRC="$SB/src"; mkdir -p "$SRC/agents-and-prompts/components"
  printf '# Swift style from source\n' > "$SRC/agents-and-prompts/components/SwiftCodeStyle.md"
  git -C "$SRC" init -q -b main
  git -C "$SRC" -c user.email=t@t -c user.name=t add -A
  git -C "$SRC" -c user.email=t@t -c user.name=t commit -qm init

  TREPO="$SB/trepo"; mkdir -p "$TREPO"; git -C "$TREPO" init -q -b main
  printf '# host\nkeep me\n' > "$TREPO/CLAUDE.md"
  git -C "$TREPO" -c user.email=t@t -c user.name=t add -A
  git -C "$TREPO" -c user.email=t@t -c user.name=t commit -qm init

  assert_rc 0 "subtree install succeeds against a local source repo" \
    env GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    "$INSTALL" "$TREPO" --method subtree --src "$SRC" --branch main
  assert_contains "$TREPO/CLAUDE.md" "@.drew-kit-src/agents-and-prompts/components/SwiftCodeStyle.md" "subtree import points into the subtree at the subpath"
  assert_not_contains "$TREPO/CLAUDE.md" "/Users/" "subtree import has no absolute machine path"
  assert_file "$TREPO/.drew-kit-src/agents-and-prompts/components/SwiftCodeStyle.md" "subtree pulled the source files into the repo"
  assert_contains "$TREPO/CLAUDE.md" "keep me" "subtree install left pre-existing prose intact"

  assert_rc 0 "uninstall (subtree) succeeds" "$UNINSTALL" "$TREPO"
  assert_no_file "$TREPO/.drew-kit-src/agents-and-prompts/components/SwiftCodeStyle.md" "uninstall removed the subtree dir"
  assert_not_contains "$TREPO/CLAUDE.md" "drew-kit imports" "uninstall removed the block (subtree)"

# ---- subtree-split: carve ONLY the components subdir out of the source, then install just that ----
# populate the full swift set in the source so no import goes unresolved
for f in SwiftAsyncAwaitConcurrency SwiftCodeCorrectnessAndSafety SwiftUIRules SwiftMisc BuildingAppleProjects; do
  printf '# %s from source\n' "$f" > "$SRC/agents-and-prompts/components/$f.md"; done
git -C "$SRC" -c user.email=t@t -c user.name=t add -A
git -C "$SRC" -c user.email=t@t -c user.name=t commit -qm "full swift set"

SPREPO="$SB/sprepo"; mkdir -p "$SPREPO"; git -C "$SPREPO" init -q -b main
printf '# host\nkeep this line\n' > "$SPREPO/CLAUDE.md"
git -C "$SPREPO" -c user.email=t@t -c user.name=t add -A
git -C "$SPREPO" -c user.email=t@t -c user.name=t commit -qm init

GENV=(env GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t)
assert_rc 0 "subtree-split install succeeds" \
  "${GENV[@]}" "$INSTALL" "$SPREPO" --method subtree-split --src "$SRC" --split-prefix agents-and-prompts/components
# split puts the components at the ROOT of .drew-kit-src (NOT under agents-and-prompts/…)
assert_file "$SPREPO/.drew-kit-src/SwiftCodeStyle.md" "split extracted ONLY the components subdir (at .drew-kit-src root)"
assert_no_file "$SPREPO/.drew-kit-src/agents-and-prompts" "split did NOT drag the source's parent dirs in"
assert_contains "$SPREPO/CLAUDE.md" "@.drew-kit-src/SwiftCodeStyle.md" "subtree-split import points at the split-root path"
assert_not_contains "$SPREPO/CLAUDE.md" "/Users/" "subtree-split import has no absolute machine path"
# it's a real subtree (git-TRACKED content), not a stray copy, AND the tree is left CLEAN (block committed)
git -C "$SPREPO" ls-files --error-unmatch .drew-kit-src/SwiftCodeStyle.md >/dev/null 2>&1 && pass "subtree-split content is git-tracked (real subtree, not a stray copy)" || fail "subtree-split content not tracked by git"
git -C "$SPREPO" diff --quiet && git -C "$SPREPO" diff --cached --quiet && pass "install left the target tree clean (import block committed)" || fail "install left the tree dirty — next run's subtree op would abort"
# the transient split branch must NOT be left littering the source repo
git -C "$SRC" rev-parse --verify -q drew-kit-split >/dev/null && fail "transient split branch leaked into source" || pass "transient split branch cleaned from source"

# install == update: change the source, re-run, the change must pull through
printf '# UPDATED upstream\n' >> "$SRC/agents-and-prompts/components/SwiftCodeStyle.md"
git -C "$SRC" -c user.email=t@t -c user.name=t commit -qam "upstream edit"
assert_rc 0 "re-run (== update) succeeds via subtree pull" \
  "${GENV[@]}" "$INSTALL" "$SPREPO" --method subtree-split --src "$SRC" --split-prefix agents-and-prompts/components
assert_contains "$SPREPO/.drew-kit-src/SwiftCodeStyle.md" "UPDATED upstream" "re-run pulled the upstream change (install == update)"

# RED: a bogus --split-prefix (subdir not in the source) must fail, not silently install nothing
red "subtree-split with a non-existent --split-prefix must fail" 1 "not found in" \
  "${GENV[@]}" "$INSTALL" "$SPREPO" --method subtree-split --src "$SRC" --split-prefix no/such/dir

# RED: a DIRTY target tree must be refused upfront (git subtree refuses anyway — fail clearly, early)
DREPO="$SB/drepo"; mkdir -p "$DREPO"; git -C "$DREPO" init -q -b main
printf 'x\n' > "$DREPO/CLAUDE.md"; git -C "$DREPO" -c user.email=t@t -c user.name=t add -A; git -C "$DREPO" -c user.email=t@t -c user.name=t commit -qm init
printf 'uncommitted edit\n' >> "$DREPO/CLAUDE.md"   # make the tree dirty
red "subtree-split on a DIRTY target tree must be refused upfront" 1 "needs a CLEAN working tree" \
  "${GENV[@]}" "$INSTALL" "$DREPO" --method subtree-split --src "$SRC"

# ---- RED controls ----
red "unknown set must fail" 1 "unknown set: cobol" "$INSTALL" "$REPO" --set cobol
printf '%s\n' "# >>> drew-kit imports (managed by drew-kit/install-into-repo.sh) >>>" > "$REPO/CLAUDE.md"  # begin marker, no end marker
# NOTE: this currently does NOT pass. install-into-repo.sh:125 computes
# be=$(grep -nF "$END" "$target" | head -1 | cut -d: -f1) — when END is absent the pipeline exits 1,
# and under `set -euo pipefail` a failing command substitution inside a plain assignment kills the
# script immediately, before line 126's "markers broken in $target — fix by hand" ever prints. The
# guard DOES abort (rc=1) and does NOT mangle the file, but it says nothing — there is no diagnostic
# substring in real stdout+stderr to match. This is a pre-existing tool defect surfaced by the red()
# migration itself, outside the scope of a test-only fix (install-into-repo.sh is not in the edit
# list). Left set to the message the code intends to emit so this documents the target behavior and
# starts passing once the script is fixed (e.g. `be=$(... ) || be=`).
red "broken markers (no end marker) must abort, not mangle" 1 "markers broken in" "$INSTALL" "$REPO"
red "missing repo argument must fail" 64 "usage: install-into-repo.sh" "$INSTALL"

finish
