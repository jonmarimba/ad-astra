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
red "unknown --method must fail" "$INSTALL" "$REPO" --method carrier-pigeon
red "submodule without --src must fail" "$INSTALL" "$REPO" --method submodule
red "subtree without --src must fail" "$INSTALL" "$REPO" --method subtree

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

# ---- RED controls ----
red "unknown set must fail" "$INSTALL" "$REPO" --set cobol
printf '%s\n' "# >>> drew-kit imports (managed by drew-kit/install-into-repo.sh) >>>" > "$REPO/CLAUDE.md"  # begin marker, no end marker
red "broken markers (no end marker) must abort, not mangle" "$INSTALL" "$REPO"
red "missing repo argument must fail" "$INSTALL"

finish
