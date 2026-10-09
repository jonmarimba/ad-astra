#!/usr/bin/env bash
# test-claude-usage-meters.sh — claude-usage-meters places its status line, writes exactly its three
# .claude/settings.json entries beside the repo's own, renders the meters, and uninstalls cleanly.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
need git "xcode-select --install"
need jq "brew install jq"
export HOME="$SB/home"; mkdir -p "$HOME"
T="$ASTRA_ROOT/tools/claude-usage-meters"
ENTRIES="$T/settings-entries.json"
SL=.astra/claude-usage-meters/statusline.sh
new_repo() { local r="$SB/$1"; mkdir -p "$r"; git -C "$r" init -q; echo "$r"; }
# Each entry's value, read back from a settings file by the entry's own path.
entries_match() {
  jq -e --slurpfile want "$ENTRIES" \
    '. as $cfg | all($want[0].entries[]; . as $e | ($cfg | getpath($e.path)) == $e.value)' "$1" >/dev/null 2>&1
}

echo "── a fresh repo"
R="$(new_repo fresh)"
bash "$T/install.sh" --into "$R" > "$SB/install.out" 2>&1
assert_eq 0 "$?" "install succeeds"
assert_file "$R/$SL" "the status line landed in the repo"
[ -x "$R/$SL" ] && pass "the status line is executable" || fail "the status line is not executable"
cmp -s "$T/statusline.sh" "$R/$SL" && pass "the placed status line is the shipped one" || fail "the placed status line differs from the shipped one"
entries_match "$R/.claude/settings.json" && pass "settings.json holds all three entries" || fail "settings.json is missing an entry: $(cat "$R/.claude/settings.json" 2>&1)"
assert_eq 3 "$(jq '[paths(scalars)] | map(.[0]) | unique | length' "$R/.claude/settings.json")" "settings.json holds nothing else at the top level"
assert_eq 3 "$(jq '.tools["claude-usage-meters"].settings | length' "$R/.astra/manifest.json")" "the manifest records the three entries"
cp "$R/.claude/settings.json" "$SB/first.json"
bash "$T/install.sh" --into "$R" > "$SB/reinstall.out" 2>&1
assert_eq 0 "$?" "a reinstall succeeds"
cmp -s "$SB/first.json" "$R/.claude/settings.json" && pass "a reinstall leaves settings.json unchanged" || fail "a reinstall changed settings.json"

echo "── the meters render through the command Claude Code runs"
FIXTURE='{"workspace":{"current_dir":"/x/my-repo"},"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1767225600},"seven_day":{"used_percentage":90.4,"resets_at":1767225600}}}'
CMD="$(jq -r '.statusLine.command' "$R/.claude/settings.json")"
(cd "$R" && printf '%s' "$FIXTURE" | CLAUDE_PROJECT_DIR="$R" COLUMNS=200 TZ=UTC sh -c "$CMD") > "$SB/wide.out" 2>&1
assert_eq 0 "$?" "the statusLine command runs"
plain="$(sed $'s/\033\\[[0-9;]*m//g' "$SB/wide.out")"
assert_eq "√ my-repo" "$(printf '%s\n' "$plain" | sed -n 1p)" "line 1 names the repo folder"
assert_eq "Session ███████████████░░░░░  75% left · resets Thu Jan 1 12:00am    Week    ██░░░░░░░░░░░░░░░░░░   9% left · resets Thu Jan 1 12:00am" \
  "$(printf '%s\n' "$plain" | sed -n 2p)" "a wide terminal shows both bars on one line"
(cd "$R" && printf '%s' "$FIXTURE" | CLAUDE_PROJECT_DIR="$R" COLUMNS=80 TZ=UTC sh -c "$CMD") > "$SB/narrow.out" 2>&1
assert_eq 3 "$(wc -l < "$SB/narrow.out" | tr -d ' ')" "a narrow terminal puts each bar on its own line"
(cd "$R" && printf '{"workspace":{"current_dir":"/x/my-repo"}}' | CLAUDE_PROJECT_DIR="$R" COLUMNS=200 sh -c "$CMD") > "$SB/nodata.out" 2>&1
assert_contains "$SB/nodata.out" "no data yet" "missing rate limits show 'no data yet', not a number"

echo "── a repo with settings of its own"
R2="$(new_repo shared)"; mkdir -p "$R2/.claude"
printf '%s\n' '{"model":"opus","enabledPlugins":{"other@market":true},"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"true"}]}]}}' > "$R2/.claude/settings.json"
cp "$R2/.claude/settings.json" "$SB/own.json"
bash "$T/install.sh" --into "$R2" > "$SB/install2.out" 2>&1
assert_eq 0 "$?" "install beside existing settings succeeds"
entries_match "$R2/.claude/settings.json" && pass "the three entries are added" || fail "an entry is missing beside existing settings"
assert_eq "true" "$(jq '.enabledPlugins["other@market"]' "$R2/.claude/settings.json")" "the repo's other plugin stays enabled"
assert_eq "opus" "$(jq -r '.model' "$R2/.claude/settings.json")" "the repo's own keys stay"
bash "$T/uninstall.sh" --into "$R2" > "$SB/uninstall2.out" 2>&1
assert_eq 0 "$?" "uninstall succeeds"
assert_eq "$(jq -S . "$SB/own.json")" "$(jq -S . "$R2/.claude/settings.json")" "uninstall restores the repo's settings exactly"

echo "── a statusLine the user edited after install"
R3="$(new_repo edited)"
bash "$T/install.sh" --into "$R3" > /dev/null 2>&1
jq '.statusLine.refreshInterval = 5' "$R3/.claude/settings.json" > "$SB/e.json" && mv "$SB/e.json" "$R3/.claude/settings.json"
bash "$T/install.sh" --into "$R3" > "$SB/install3.out" 2>&1
assert_eq 0 "$?" "a reinstall over an edited entry succeeds"
assert_eq 5 "$(jq '.statusLine.refreshInterval' "$R3/.claude/settings.json")" "the reinstall keeps the edit"
assert_contains "$SB/install3.out" "kept your edited setting statusLine" "the reinstall says it kept the edit"
bash "$T/uninstall.sh" --into "$R3" > "$SB/uninstall3.out" 2>&1
assert_eq 5 "$(jq '.statusLine.refreshInterval' "$R3/.claude/settings.json")" "uninstall keeps the edited entry"
assert_eq "null" "$(jq '.enabledPlugins' "$R3/.claude/settings.json")" "uninstall still removes the unedited entries"

echo "── uninstall from the fresh repo"
bash "$T/uninstall.sh" --into "$R" > "$SB/uninstall.out" 2>&1
assert_eq 0 "$?" "uninstall succeeds"
assert_no_file "$R/$SL" "the status line is gone"
assert_no_file "$R/.claude" "settings.json held only our entries, so it and .claude are gone"
assert_no_file "$R/.astra" "nothing astra-shaped is left"

echo "── RED controls"
R4="$(new_repo foreign)"; mkdir -p "$R4/.claude"
printf '%s\n' '{"statusLine":{"type":"command","command":"echo mine"}}' > "$R4/.claude/settings.json"
red "a repo's own statusLine is never replaced" 65 "already sets statusLine" bash "$T/install.sh" --into "$R4"
assert_eq '{"statusLine":{"type":"command","command":"echo mine"}}' "$(jq -c . "$R4/.claude/settings.json")" "the refused install left the settings alone"
assert_no_file "$R4/.astra" "the refused install placed no files"
red "install without --into" 64 "usage: --into <repo>" bash "$T/install.sh"
R5="$(new_repo badjson)"; mkdir -p "$R5/.claude"; printf '{"oops":' > "$R5/.claude/settings.json"
red "an unreadable settings.json is never rewritten" 65 "is unreadable" bash "$T/install.sh" --into "$R5"
assert_eq '{"oops":' "$(cat "$R5/.claude/settings.json")" "the unreadable settings.json is untouched"
R6="$(new_repo badshape)"; mkdir -p "$R6/.claude"; printf '%s\n' '{"enabledPlugins":["not-an-object"]}' > "$R6/.claude/settings.json"
red "a settings key of the wrong shape refuses before any file lands" 65 "enabledPlugins is not an object" env ASTRA_FORCE=1 bash "$T/install.sh" --into "$R6"
assert_no_file "$R6/.astra" "the wrong-shape refusal placed no files"
finish
