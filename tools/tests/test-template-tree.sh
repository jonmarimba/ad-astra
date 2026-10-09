#!/usr/bin/env bash
# test-template-tree.sh — templates that contain templates: the printed tree, a parent that
# holds two templates sharing a tool, and uninstall that reasons from the RECORD of what was
# installed rather than from a catalogue that may have changed since.
#
# Real template.py, real check-prose and check-banned-phrases installers (file copies, no
# network), a test catalogue injected through ASTRA_TEMPLATES_JSON.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need python3 "xcode-select --install"
need git "xcode-select --install"
TPL="$ASTRA_ROOT/tools/lib/template.py"

CAT="$SB/templates.json"
cat > "$CAT" <<'EOF'
{"templates": {
  "leaf-prose":  {"description": "one tool", "tools": ["check-prose"]},
  "leaf-banned": {"description": "two tools, one shared with leaf-prose", "tools": ["check-prose", "check-banned-phrases"]},
  "middle":      {"description": "holds a template and a tool", "templates": ["leaf-prose"], "tools": ["check-banned-phrases"]},
  "top":         {"description": "holds two templates that share a tool", "templates": ["middle", "leaf-banned"], "tools": []},
  "cyc-a":       {"description": "half a cycle", "templates": ["cyc-b"], "tools": []},
  "cyc-b":       {"description": "other half", "templates": ["cyc-a"], "tools": []},
  "dangling":    {"description": "names a template that is not in the catalogue", "templates": ["gone"], "tools": []},
  "with-machine": {"description": "a repo tool and a machine tool", "tools": ["check-prose", "axe"]}
}}
EOF
tpl() { ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" "$@"; }

echo "== the tree"
tpl tree top > "$SB/tree-top.out" 2>&1
assert_eq 0 "$?" "tree <name> succeeds"
assert_contains "$SB/tree-top.out" "top/" "the root is named, with a slash that marks a template"
assert_contains "$SB/tree-top.out" "middle/" "a member template appears under its parent"
assert_contains "$SB/tree-top.out" "leaf-prose/" "and a template inside that member appears under it"
assert_contains "$SB/tree-top.out" "check-prose" "tools are leaves"
assert_contains "$SB/tree-top.out" "leaf-banned/" "the second member template appears too"
depth_check="$(awk '/leaf-prose\//{print index($0,"leaf-prose/")} /^top\//{print index($0,"top/")} /middle\//{print index($0,"middle/")}' "$SB/tree-top.out" | tr '\n' ' ')"
case "$depth_check" in "1 3 5 ") pass "each level is indented deeper than its parent" ;; *) fail "indentation does not deepen with nesting (columns: $depth_check)" ;; esac
tpl tree > "$SB/tree-all.out" 2>&1
assert_eq 0 "$?" "tree with no name prints every root"
assert_contains "$SB/tree-all.out" "top/" "the all-roots view includes the parent nobody contains"
if grep -q '^middle/' "$SB/tree-all.out"; then fail "a template that another template contains is printed as a root"; else pass "a contained template is shown only under its parent, not as a root"; fi
tpl tree with-machine > "$SB/tree-machine.out" 2>&1
assert_contains "$SB/tree-machine.out" "axe  [machine]" "a machine-level tool is tagged, so the tree shows what level each piece lives at"
if grep -q 'check-prose  \[' "$SB/tree-machine.out"; then fail "a repo-level tool was tagged as if it needed the machine"; else pass "a repo-level tool carries no tag"; fi
tpl tree cyc-a > "$SB/tree-cyc.out" 2>&1
assert_eq 0 "$?" "a cycle does not hang or crash the tree"
assert_contains "$SB/tree-cyc.out" "cycle" "and the tree says so"
tpl tree dangling > "$SB/tree-dangling.out" 2>&1
assert_contains "$SB/tree-dangling.out" "gone" "a missing member is named in the tree"
assert_contains "$SB/tree-dangling.out" "missing" "and marked missing"
tpl tree no-such-template > "$SB/tree-bad.out" 2>&1
assert_eq 66 "$?" "RED: tree of an unknown name exits 66"
assert_contains "$SB/tree-bad.out" "no such template" "RED: and says why"

echo "== a parent that holds two templates sharing a tool"
tpl show top > "$SB/show-top.out" 2>&1
assert_eq 1 "$(grep -o 'check-prose' "$SB/show-top.out" | wc -l | tr -d ' ')" "show lists a shared tool once in the resolved line"
REPO="$SB/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q
tpl install top --into "$REPO" > "$SB/install-top.out" 2>&1
assert_eq 0 "$?" "installing the parent succeeds"
assert_file "$REPO/.astra/check-prose/check-prose.js" "a tool from the deepest template landed"
assert_file "$REPO/.astra/check-banned-phrases/check-banned-phrases.sh" "a tool from the sibling template landed"
assert_eq 1 "$(grep -c 'installed  check-prose' "$SB/install-top.out" | tr -d ' ')" "the shared tool was installed once, not once per path"
tpl uninstall top --into "$REPO" > "$SB/uninstall-top.out" 2>&1
assert_eq 0 "$?" "uninstalling the parent succeeds"
assert_no_file "$REPO/.astra/check-prose/check-prose.js" "the shared tool is gone after the last claimant leaves"
assert_no_file "$REPO/.astra/check-banned-phrases/check-banned-phrases.sh" "and so is the other"

echo "== uninstall removes what the record says was installed"
# The catalogue changes after install: the leaf loses its tool. The repo still holds that tool.
tpl install middle --into "$REPO" > /dev/null 2>&1
assert_file "$REPO/.astra/check-prose/check-prose.js" "(setup) middle installed check-prose through leaf-prose"
CAT2="$SB/templates-later.json"
cat > "$CAT2" <<'EOF'
{"templates": {
  "leaf-prose": {"description": "now empty", "tools": []},
  "middle":     {"description": "holds a template and a tool", "templates": ["leaf-prose"], "tools": ["check-banned-phrases"]}
}}
EOF
ASTRA_TEMPLATES_JSON="$CAT2" python3 "$TPL" uninstall middle --into "$REPO" > "$SB/un-later.out" 2>&1
assert_eq 0 "$?" "uninstall succeeds against a catalogue that has changed"
assert_no_file "$REPO/.astra/check-prose/check-prose.js" "a tool the catalogue dropped from a member is still removed, because the record says it was installed"
assert_no_file "$REPO/.astra/check-banned-phrases/check-banned-phrases.sh" "and the rest of the template is removed too"
tpl install middle --into "$REPO" > /dev/null 2>&1
CAT3="$SB/templates-renamed.json"
printf '%s\n' '{"templates": {"leaf-prose": {"description": "x", "tools": ["check-prose"]}}}' > "$CAT3"
ASTRA_TEMPLATES_JSON="$CAT3" python3 "$TPL" uninstall middle --into "$REPO" > "$SB/un-renamed.out" 2>&1
assert_eq 0 "$?" "a template that left the catalogue can still be uninstalled while the repo records it"
assert_no_file "$REPO/.astra/check-prose/check-prose.js" "and its tools come out"
tpl uninstall middle --into "$REPO" > "$SB/un-twice.out" 2>&1
assert_eq 65 "$?" "RED: uninstalling something the repo does not record is still refused"
assert_contains "$SB/un-twice.out" "not recorded as installed" "RED: and says so"
ASTRA_TEMPLATES_JSON="$CAT3" python3 "$TPL" uninstall no-such-anywhere --into "$REPO" > "$SB/un-unknown.out" 2>&1
assert_eq 66 "$?" "RED: an unknown name that the repo does not record exits 66"

echo "== removing a tool that arrived through a template"
tpl install leaf-prose --into "$REPO" > /dev/null 2>&1
tpl uninstall check-prose --into "$REPO" > "$SB/un-held.out" 2>&1
assert_eq 65 "$?" "RED: a tool that only a template holds cannot be removed alone"
assert_contains "$SB/un-held.out" "came in through: leaf-prose" "and the refusal names the template that holds it"
assert_file "$REPO/.astra/check-prose/check-prose.js" "and the tool is still installed"
tpl uninstall leaf-prose --into "$REPO" > /dev/null 2>&1

echo "== the README shows the real tree"
if grep -q '<!-- template-tree:start -->' "$ASTRA_ROOT/README.md"; then
  got="$(awk '/<!-- template-tree:start -->/{f=1;next} /<!-- template-tree:end -->/{f=0} f' "$ASTRA_ROOT/README.md" | grep -v '^```')"
  want="$(python3 "$TPL" tree)"
  assert_eq "$want" "$got" "the tree in README.md matches template.py tree, so it cannot go stale"
else
  fail "README.md has no <!-- template-tree:start --> block"
fi
finish
