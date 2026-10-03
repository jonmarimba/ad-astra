#!/usr/bin/env bash
# test-astra-update-log.sh — the updater's --log writes on CHANGE OF STATE, never per run.
#
# The post-commit hook used to redirect every run into .astra/update.log, so a tracked
# log gained one "14 current" line per commit and dirtied the tree after each commit it
# was itself committed in. Jonathan, 2026-10-02: "An updater shouldn't shit in its tracking
# file when nothing happened. Think cocoapods." --log now appends one dated line when the
# summary changes or when any file was updated, flagged or lost, and nothing otherwise.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need python3 "xcode-select --install"
CANON="$HERE/../lib/astra-update"

WORK="$SB/work"
mkdir -p "$WORK/my-astra/tools/footool" "$WORK/consumer/.astra/footool"
printf 'echo v1\n' > "$WORK/my-astra/tools/footool/foo.sh"
printf 'echo v1\n' > "$WORK/consumer/.astra/footool/foo.sh"
V1SHA="$(python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()[:16])" "$WORK/consumer/.astra/footool/foo.sh")"
cat > "$WORK/consumer/.astra/manifest.json" <<EOF
{"tools": {"footool": {"source": "$WORK/my-astra", "files": {"foo.sh": "$V1SHA"}}}}
EOF
cp "$CANON" "$WORK/consumer/.astra/astra-update"
chmod +x "$WORK/consumer/.astra/astra-update"
LOG="$WORK/consumer/.astra/update.log"
UPD="$WORK/consumer/.astra/astra-update"

# --- first run on a current install: one dated line, because there was no prior state ---
"$UPD" --pull --log "$LOG" >/dev/null 2>&1
assert_file "$LOG" "first run creates the log"
assert_eq "1" "$(wc -l < "$LOG" | tr -d ' ')" "first run writes exactly one line"
assert_contains "$LOG" "1 current" "and it carries the summary"
first="$(head -n 1 "$LOG")"
case "$first" in
  20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]\ \ *) pass "the line is date-stamped" ;;
  *) fail "the line is date-stamped (got '$first')" ;;
esac

# --- five quiet runs: the log does not grow ---
for _ in 1 2 3 4 5; do "$UPD" --pull --log "$LOG" >/dev/null 2>&1; done
assert_eq "1" "$(wc -l < "$LOG" | tr -d ' ')" "five runs with nothing to do add nothing"

# --- the source moves on: --pull updates, and that is a state change worth one entry ---
printf 'echo v2\n' > "$WORK/my-astra/tools/footool/foo.sh"
"$UPD" --pull --log "$LOG" >/dev/null 2>&1
assert_contains "$WORK/consumer/.astra/footool/foo.sh" "v2" "the file was updated"
assert_contains "$LOG" "updated      footool/foo.sh" "the update is recorded"
assert_contains "$LOG" "1 updated" "with the changed summary"
assert_eq "3" "$(wc -l < "$LOG" | tr -d ' ')" "one summary line plus one detail line were added"

# --- quiet again after the update: still nothing new ---
"$UPD" --pull --log "$LOG" >/dev/null 2>&1
"$UPD" --pull --log "$LOG" >/dev/null 2>&1
assert_eq "4" "$(wc -l < "$LOG" | tr -d ' ')" "the first quiet run after an update logs the new steady state once"
"$UPD" --pull --log "$LOG" >/dev/null 2>&1
assert_eq "4" "$(wc -l < "$LOG" | tr -d ' ')" "and later quiet runs add nothing"

# --- a local edit is a human-decision state and is logged ---
printf 'echo mine\n' > "$WORK/consumer/.astra/footool/foo.sh"
"$UPD" --pull --log "$LOG" >/dev/null 2>&1
assert_contains "$LOG" "LOCAL EDITS" "a locally modified file is recorded"

# --- RED-capable: a PERSISTENT local edit logs ONCE, not on every run. The old
#     `if events or summary != last` re-appended an identical LOCAL EDITS block each run,
#     because the event is regenerated while the condition holds (ghost-openclaw on d9dd98b0).
after_edit="$(wc -l < "$LOG" | tr -d ' ')"
"$UPD" --pull --log "$LOG" >/dev/null 2>&1
"$UPD" --pull --log "$LOG" >/dev/null 2>&1
"$UPD" --pull --log "$LOG" >/dev/null 2>&1
assert_eq "$after_edit" "$(wc -l < "$LOG" | tr -d ' ')" "a persistent local edit does not re-log on every run"

# --- RED control: --log with no path is refused, rc 2, and says so ---
red "--log without a path is refused" 2 "--log needs a file path" "$UPD" --log

# --- stdout is unchanged by --log: a caller still sees the summary ---
"$UPD" --log "$LOG" >"$SB/stdout.txt" 2>/dev/null
assert_contains "$SB/stdout.txt" "locally modified" "stdout still carries the summary"

finish
