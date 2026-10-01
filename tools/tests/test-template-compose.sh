#!/usr/bin/env bash
# test-template-compose.sh — templates containing templates (INVENTORY item 4; the
# SPEC's composition model: "a template may also list other templates as members, and
# that is the point — composition is the mechanism, not a convenience").
#
# Exercised against the REAL template.py and the REAL check-prose installer (file
# copies, no network), with a test catalogue injected through ASTRA_TEMPLATES_JSON.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need python3 "xcode-select --install"
need git "system-present"
TPL="$HERE/../lib/template.py"

REPO="$SB/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q

CAT="$SB/templates.json"
cat > "$CAT" <<'EOF'
{"templates": {
  "base-writing": {"description": "the leaf", "tools": ["check-prose"]},
  "composed":     {"description": "a wrapper whose only member is another template",
                   "templates": ["base-writing"], "tools": []},
  "cyclic-a":     {"description": "half a cycle", "templates": ["cyclic-b"], "tools": []},
  "cyclic-b":     {"description": "other half", "templates": ["cyclic-a"], "tools": []},
  "bad-member":   {"description": "names a template that does not exist",
                   "templates": ["no-such-template"], "tools": []}
}}
EOF

# --- installing a composed template installs its members' tools ---
out="$SB/install.out"
ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" install composed --into "$REPO" >"$out" 2>&1
assert_eq "0" "$?" "installing the composed template succeeds"
assert_file "$REPO/.astra/check-prose/check-prose.js" \
  "the member template's tool actually landed — composition resolves transitively"

# --- show resolves the closure, so a human sees what an install will do ---
out="$SB/show.out"
ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" show composed >"$out" 2>&1
assert_contains "$out" "check-prose" "show displays the RESOLVED tool set, not the empty flat array"

# --- overlap claims are transitive: a composed claim protects a shared tool ---
ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" install base-writing --into "$REPO" >/dev/null 2>&1
out="$SB/uninstall.out"
ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" uninstall composed --into "$REPO" >"$out" 2>&1
assert_contains "$out" "KEPT" "uninstalling the wrapper keeps the tool the leaf still claims"
assert_file "$REPO/.astra/check-prose/check-prose.js" "and the shared tool survives on disk"
ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" uninstall base-writing --into "$REPO" >/dev/null 2>&1
assert_no_file "$REPO/.astra/check-prose/check-prose.js" \
  "removing the last claimant removes the tool"

# --- an unresolvable MEMBER of a still-installed wrapper does not crash uninstall,
# --- and does not let a sibling delete a tool the wrapper still claims (adv round #4/#7) ---
CAT2="$SB/templates2.json"
cat > "$CAT2" <<'EOF'
{"templates": {
  "leafone": {"description": "installs check-prose", "tools": ["check-prose"]},
  "wrapper": {"description": "claims check-prose only THROUGH a member that will vanish",
              "templates": ["gonemember"], "tools": []},
  "gonemember": {"description": "resolves to check-prose", "tools": ["check-prose"]}
}}
EOF
REPO2="$SB/repo2"; mkdir -p "$REPO2"; git -C "$REPO2" init -q
ASTRA_TEMPLATES_JSON="$CAT2" python3 "$TPL" install leafone --into "$REPO2" >/dev/null 2>&1
ASTRA_TEMPLATES_JSON="$CAT2" python3 "$TPL" install wrapper --into "$REPO2" >/dev/null 2>&1
# Now the catalogue loses gonemember — wrapper's only link to check-prose is unresolvable.
CAT3="$SB/templates3.json"
cat > "$CAT3" <<'EOF'
{"templates": {
  "leafone": {"description": "installs check-prose", "tools": ["check-prose"]},
  "wrapper": {"description": "member now missing", "templates": ["gonemember"], "tools": []}
}}
EOF
out="$SB/uninstall-crash.out"
ASTRA_TEMPLATES_JSON="$CAT3" python3 "$TPL" uninstall leafone --into "$REPO2" >"$out" 2>&1
rc=$?
assert_not_contains "$out" "Traceback" "uninstalling a leaf does not crash on a wrapper's unresolvable member"
assert_eq "0" "$rc" "and it exits cleanly"
assert_file "$REPO2/.astra/check-prose/check-prose.js" \
  "check-prose survives — the wrapper still claims it transitively, so it is NOT deleted"

# --- a cycle is a loud, named refusal, not a stack overflow or a silent no-op ---
red "a template cycle is refused by name" 65 "template cycle" \
  env ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" install cyclic-a --into "$REPO"

# --- an unknown member template is a loud refusal too ---
red "a member template that does not exist is refused by name" 65 "no such template: no-such-template" \
  env ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" install bad-member --into "$REPO"

finish
