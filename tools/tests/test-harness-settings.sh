#!/usr/bin/env bash
# test-harness-settings.sh — apply edits real config files (copies of the real shapes, under a
# sandboxed $HOME), undo restores them byte-identical, and the deny/allow merge never clobbers
# what was already there.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
HS_BIN="$HERE/../harness-settings/harness-settings.sh"
# --scope global is LOAD-BEARING. The tool's DEFAULT scope is "project", which resolves to the
# git root of the current directory — this repo. Every fixture below is written under a
# sandboxed $HOME and every assertion reads from there, so without this the tool edits
# js-db-ad-astra's own .claude/settings.json while the test measures $HOME and reports
# "want opus got sonnet". It also left .claude/, .codex/ and .qwen/ behind in the repo, which
# is how the failure was finally traced on 2026-08-27.
HS() { "$HS_BIN" --scope global "$@"; }
HS="$HS_BIN"
need jq "brew install jq"
python3 -c "import tomlkit" 2>/dev/null || { fail "python tomlkit missing (tools/harness-settings/install.sh)"; finish; exit 1; }

# tomlkit lives in pip's --user site under the REAL home; sandboxing $HOME below would hide it,
# so pin the user-site onto PYTHONPATH first (first run failed exactly here)
export PYTHONPATH="$(python3 -m site --user-site):${PYTHONPATH:-}"
export HOME="$SB/home"           # the script derives every config path from $HOME
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.qwen"
cat > "$HOME/.claude/settings.json" <<'EOF'
{"model":"sonnet","permissions":{"deny":["Read(secrets.txt)"],"allow":["Bash(pwd:*)"]}}
EOF
cat > "$HOME/.codex/config.toml" <<'EOF'
# a comment tomlkit must preserve
model = "gpt-5.2-codex"
model_verbosity = "high"
EOF
cat > "$HOME/.qwen/settings.json" <<'EOF'
{"telemetry":{"enabled":true},"theme":"dark"}
EOF
cp "$HOME/.claude/settings.json" "$SB/claude.orig"
cp "$HOME/.codex/config.toml"    "$SB/codex.orig"
cp "$HOME/.qwen/settings.json"   "$SB/qwen.orig"

# ---- apply: asserted by effect on each config ----
assert_rc 0 "apply succeeds" "$HS_BIN" --scope global apply
assert_eq "opus"  "$(jq -r .model "$HOME/.claude/settings.json")"       "claude model set"
assert_eq "xhigh" "$(jq -r .effortLevel "$HOME/.claude/settings.json")" "claude effort set"
assert_eq "true"  "$(jq '.permissions.deny | index("Read(secrets.txt)") != null' "$HOME/.claude/settings.json")" "pre-existing deny entry SURVIVED the merge"
assert_eq "true"  "$(jq '.permissions.deny | index("Bash(git push:*)") != null' "$HOME/.claude/settings.json")"  "new deny entry merged in"
assert_eq "high"  "$(jq -r .thinking "$HOME/.qwen/settings.json")"      "qwen thinking set"
assert_eq "false" "$(jq -r .telemetry.enabled "$HOME/.qwen/settings.json")" "qwen telemetry off"
assert_eq "xhigh" "$(python3 -c "import tomlkit,sys;print(tomlkit.parse(open(sys.argv[1]).read())['model_reasoning_effort'])" "$HOME/.codex/config.toml")" "codex effort set"
assert_contains "$HOME/.codex/config.toml" "# a comment tomlkit must preserve" "codex TOML comment preserved"
assert_eq "gpt-5.2-codex" "$(python3 -c "import tomlkit,sys;print(tomlkit.parse(open(sys.argv[1]).read())['model'])" "$HOME/.codex/config.toml")" "codex unrelated key untouched"

# ---- double-apply: deny/allow lists must not grow duplicates ----
HS apply >/dev/null 2>&1
d1="$(jq '.permissions.deny | length' "$HOME/.claude/settings.json")"
HS apply >/dev/null 2>&1
d2="$(jq '.permissions.deny | length' "$HOME/.claude/settings.json")"
assert_eq "$d1" "$d2" "third apply added no duplicate deny entries"

# ---- undo: byte-identical restore of the MOST RECENT backup ----
assert_rc 0 "undo succeeds" "$HS_BIN" --scope global undo
# note: undo restores the latest backup, which (after three applies) is the twice-applied state —
# so compare against what apply itself backed up, not the pristine originals
# The backup root is SCOPE-AWARE: $HOME/.harness-settings-backups/<scope>. Reading it without
# the scope segment worked only while the tests ran under the default project scope.
BKROOT="$HOME/.harness-settings-backups/global"
ts="$(cat "$BKROOT/latest")"
cmp -s "$BKROOT/$ts/claude_settings.json" "$HOME/.claude/settings.json" && pass "undo restored claude byte-identical to its backup" || fail "undo did not restore claude byte-identical"
cmp -s "$BKROOT/$ts/codex_config.toml" "$HOME/.codex/config.toml" && pass "undo restored codex byte-identical to its backup" || fail "undo did not restore codex byte-identical"

# ---- full-cycle reversibility: fresh HOME, one apply, one undo -> pristine originals ----
export HOME="$SB/home2"; mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.qwen"
cp "$SB/claude.orig" "$HOME/.claude/settings.json"; cp "$SB/codex.orig" "$HOME/.codex/config.toml"; cp "$SB/qwen.orig" "$HOME/.qwen/settings.json"
# tautology guard: the round trip only proves reversibility if apply actually CHANGED the file
# (first run of this suite "passed" here while apply was exiting early — exactly the class)
assert_rc 0 "round-trip apply succeeds" "$HS_BIN" --scope global apply
cmp -s "$SB/claude.orig" "$HOME/.claude/settings.json" && fail "apply changed nothing — round-trip would be vacuous" || pass "apply really mutated the config (round-trip is a real claim)"
assert_rc 0 "round-trip undo succeeds" "$HS_BIN" --scope global undo
cmp -s "$SB/claude.orig" "$HOME/.claude/settings.json" && pass "apply+undo round-trip restored claude pristine" || fail "round-trip did not restore claude pristine"
cmp -s "$SB/codex.orig"  "$HOME/.codex/config.toml"    && pass "apply+undo round-trip restored codex pristine"  || fail "round-trip did not restore codex pristine"
cmp -s "$SB/qwen.orig"   "$HOME/.qwen/settings.json"   && pass "apply+undo round-trip restored qwen pristine"   || fail "round-trip did not restore qwen pristine"

# ---- RED controls ----
export HOME="$SB/home3"; mkdir -p "$HOME"
red "undo with no backups must fail" "$HS_BIN" --scope global undo
red "unknown subcommand must fail" "$HS_BIN" --scope global frobnicate
# a config jq can't parse must FAIL the apply — not print per-config success + 'DONE.' (the
# false-success shape: believing the safety deny-rules are live when nothing changed)
mkdir -p "$HOME/.claude"
printf '{"model":"sonnet",}\n' > "$HOME/.claude/settings.json"   # trailing comma = invalid JSON
out="$("$HS_BIN" --scope global apply 2>/dev/null)"; rc=$?
assert_eq "1" "$rc" "apply exits nonzero on an unparseable config"
printf '%s' "$out" | grep -qF "DONE." && fail "apply printed DONE. despite a failed edit" || pass "no false DONE. on failure"
assert_contains "$HOME/.claude/settings.json" '{"model":"sonnet",}' "broken config left byte-identical (no partial write)"

finish
