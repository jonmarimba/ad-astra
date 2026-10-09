#!/usr/bin/env bash
# test-usage-meters.sh — usage-meters places its status lines and Claude Code plugin, writes exactly
# its entries into .claude/settings.json, .qwen/settings.json and .codex/config.toml beside each
# repo's own, renders the meters, keeps user edits, refuses foreign values, and uninstalls exactly.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
need git "xcode-select --install"
need jq "brew install jq"
# astra itself runs on the python3 lib.sh puts first (the system 3.9); only the TOML check needs 3.11+.
TOML_PY=""
for p in python3.14 python3.13 python3.12 python3.11; do command -v "$p" >/dev/null 2>&1 && { TOML_PY="$p"; break; }; done
[ -n "$TOML_PY" ] && "$TOML_PY" -c 'import tomllib' && pass "$TOML_PY has tomllib to check the TOML astra writes" \
  || fail "no python3.11 or newer for tomllib (brew install python)"
export HOME="$SB/home"; mkdir -p "$HOME"
T="$ASTRA_ROOT/tools/usage-meters"
ENTRIES="$T/settings-entries.json"
SKILL=.claude/skills/astra-usage-meters
PLACED=".astra/usage-meters/statusline.sh:tools/usage-meters/statusline.sh
.astra/usage-meters/statusline-qwen.sh:tools/usage-meters/statusline-qwen.sh
$SKILL/.claude-plugin/plugin.json:tools/usage-meters/claude-plugin/.claude-plugin/plugin.json
$SKILL/hooks/hooks.json:tools/usage-meters/claude-plugin/hooks/hooks.json
$SKILL/hooks/register.tsx:tools/usage-meters/claude-plugin/hooks/register.tsx
$SKILL/bin/tally_tokens.py:tools/usage-meters/claude-plugin/bin/tally_tokens.py
$SKILL/types/index.d.ts:tools/usage-meters/claude-plugin/types/index.d.ts"
new_repo() { local r="$SB/$1"; mkdir -p "$r"; git -C "$r" init -q; echo "$r"; }
toml_json() { "$TOML_PY" -c 'import json,sys,tomllib; print(json.dumps(tomllib.load(open(sys.argv[1],"rb")),sort_keys=True))' "$1"; }
# Every entry's value, read back from its own file by its own path.
entries_match() {
  local r="$1" n i file path want got
  n="$(jq '.entries | length' "$ENTRIES")"
  for ((i = 0; i < n; i++)); do
    file="$(jq -r ".entries[$i].file" "$ENTRIES")"; path="$(jq -c ".entries[$i].path" "$ENTRIES")"
    want="$(jq -cS ".entries[$i].value" "$ENTRIES")"
    case "$file" in
      *.toml) got="$(toml_json "$r/$file" 2>/dev/null | jq -cS --argjson p "$path" 'getpath($p)')" ;;
      *) got="$(jq -cS --argjson p "$path" 'getpath($p)' "$r/$file" 2>/dev/null)" ;;
    esac
    [ "$want" = "$got" ] || { echo "$file $path: want $want got $got"; return 1; }
  done
}
# JSON compares by content (astra rewrites a JSON file it edits with its own indentation, as the hook
# writer always has); TOML compares byte for byte, because astra edits it line by line.
snapshot() { local r="$1" f; for f in .claude/settings.json .qwen/settings.json; do
  printf '== %s\n' "$f"; jq -S . "$r/$f" 2>/dev/null || echo "(absent)"; done
  printf '== .codex/config.toml\n'; cat "$r/.codex/config.toml" 2>/dev/null || echo "(absent)"; }

echo "── a fresh repo"
R="$(new_repo fresh)"
bash "$T/install.sh" --into "$R" > "$SB/install.out" 2>&1
assert_eq 0 "$?" "install succeeds"
while IFS=: read -r dest src; do
  cmp -s "$ASTRA_ROOT/$src" "$R/$dest" && pass "placed $dest" || fail "$dest is missing or differs from $src"
done <<< "$PLACED"
[ -x "$R/.astra/usage-meters/statusline.sh" ] && [ -x "$R/.astra/usage-meters/statusline-qwen.sh" ] \
  && pass "both status lines are executable" || fail "a status line is not executable"
assert_no_file "$R/$SKILL/hooks/register.test.tsx" "the plugin's own tests stay in astra"
out="$(entries_match "$R")" && pass "all three config files hold their entries" || fail "an entry is wrong: $out"
assert_eq '["statusLine"]' "$(jq -c 'keys' "$R/.claude/settings.json")" ".claude/settings.json holds only the statusLine"
assert_eq '{"ui":["statusLine"]}' "$(jq -c '{ui: (.ui | keys)}' "$R/.qwen/settings.json")" ".qwen/settings.json holds only ui.statusLine"
assert_eq '[tui]
status_line = ["project-root", "context-used", "five-hour-limit", "weekly-limit", "used-tokens"]' "$(cat "$R/.codex/config.toml")" ".codex/config.toml is one [tui] table with one key"
assert_eq 3 "$(jq '.tools["usage-meters"].settings | length' "$R/.astra/manifest.json")" "the manifest records the three entries"
snapshot "$R" > "$SB/first.txt"
bash "$T/install.sh" --into "$R" > "$SB/reinstall.out" 2>&1
assert_eq 0 "$?" "a reinstall succeeds"
snapshot "$R" | cmp -s "$SB/first.txt" - && pass "a reinstall changes no config file" || fail "a reinstall changed a config file"

echo "── the status lines render through the commands written into the configs"
CLAUDE_IN='{"workspace":{"current_dir":"/x/my-repo"},"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1767225600},"seven_day":{"used_percentage":90.4,"resets_at":1767225600}}}'
CMD="$(jq -r '.statusLine.command' "$R/.claude/settings.json")"
(cd "$R" && printf '%s' "$CLAUDE_IN" | CLAUDE_PROJECT_DIR="$R" COLUMNS=200 TZ=UTC sh -c "$CMD") > "$SB/claude.out" 2>&1
assert_eq 0 "$?" "the Claude Code statusLine command runs"
plain="$(sed $'s/\033\\[[0-9;]*m//g' "$SB/claude.out")"
assert_eq "√ my-repo" "$(printf '%s\n' "$plain" | sed -n 1p)" "Claude line 1 names the folder"
assert_eq "Session ███████████████░░░░░  75% left · resets Thu Jan 1 12:00am    Week    ██░░░░░░░░░░░░░░░░░░   9% left · resets Thu Jan 1 12:00am" \
  "$(printf '%s\n' "$plain" | sed -n 2p)" "Claude line 2 shows both bars on a wide terminal"
(cd "$R" && printf '%s' "$CLAUDE_IN" | CLAUDE_PROJECT_DIR="$R" COLUMNS=80 TZ=UTC sh -c "$CMD") > "$SB/narrow.out" 2>&1
assert_eq 3 "$(wc -l < "$SB/narrow.out" | tr -d ' ')" "a narrow terminal puts each bar on its own line"
QWEN_IN='{"workspace":{"current_dir":"/x/my-repo"},"context_window":{"current_usage":134400},"metrics":{"models":{"a":{"tokens":{"prompt":30000,"cached":10000,"completion":5000,"thoughts":2000}},"b":{"tokens":{"prompt":1000,"completion":200}}}}}'
QCMD="$(jq -r '.ui.statusLine.command' "$R/.qwen/settings.json")"
(cd "$R" && printf '%s' "$QWEN_IN" | sh -c "$QCMD") > "$SB/qwen.out" 2>&1
assert_eq 0 "$?" "the Qwen Code statusLine command runs from the repo folder"
assert_eq "√ my-repo
Context 134k    NCR tok 26k this session" "$(sed $'s/\033\\[[0-9;]*m//g' "$SB/qwen.out")" "Qwen shows the folder, the context and prompt - cached + completion"
(cd "$R" && printf '{"workspace":{"current_dir":"/x/my-repo"},"context_window":{"current_usage":0}}' | sh -c "$QCMD" | sed $'s/\033\\[[0-9;]*m//g') > "$SB/qwen0.out" 2>&1
assert_contains "$SB/qwen0.out" "Context –" "Qwen shows a dash before the first response, not a zero"

echo "── repos with configs of their own"
R2="$(new_repo shared)"; mkdir -p "$R2/.claude" "$R2/.qwen" "$R2/.codex"
printf '%s\n' '{"model":"opus","hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"true"}]}]}}' > "$R2/.claude/settings.json"
printf '%s\n' '{"mcpServers":{"x":{"command":"x"}},"ui":{"theme":"dark"}}' > "$R2/.qwen/settings.json"
printf '%s\n' '# repo codex config' 'model = "gpt-5"' '' '[tui]' '# keep me' 'animations = false' '' '[mcp_servers.xcode]' 'command = "xcrun"' > "$R2/.codex/config.toml"
snapshot "$R2" > "$SB/own.txt"
bash "$T/install.sh" --into "$R2" > "$SB/install2.out" 2>&1
assert_eq 0 "$?" "install beside existing configs succeeds"
out="$(entries_match "$R2")" && pass "the entries are added to all three" || fail "an entry is wrong beside existing configs: $out"
assert_eq "opus" "$(jq -r '.model' "$R2/.claude/settings.json")" "the repo's Claude settings stay"
assert_eq "dark" "$(jq -r '.ui.theme' "$R2/.qwen/settings.json")" "the repo's Qwen ui settings stay beside ui.statusLine"
assert_eq '{"animations":false,"command":"xcrun","model":"gpt-5"}' \
  "$(toml_json "$R2/.codex/config.toml" | jq -c '{animations: .tui.animations, command: .mcp_servers.xcode.command, model}')" "the repo's Codex settings stay, and the file still parses"
bash "$T/uninstall.sh" --into "$R2" > "$SB/uninstall2.out" 2>&1
assert_eq 0 "$?" "uninstall succeeds"
snapshot "$R2" | cmp -s "$SB/own.txt" - && pass "uninstall restores the JSON content and the TOML bytes" \
  || { fail "uninstall did not restore the configs exactly"; snapshot "$R2" | diff "$SB/own.txt" - >&2; }
R2b="$(new_repo codex-other-tables)"; mkdir -p "$R2b/.codex"
printf '%s\n' 'model = "gpt-5"' '' '[mcp_servers.xcode]' 'command = "xcrun"' > "$R2b/.codex/config.toml"
cp "$R2b/.codex/config.toml" "$SB/codex-own.toml"
bash "$T/install.sh" --into "$R2b" > /dev/null 2>&1
assert_eq '["gpt-5","xcrun",5]' "$(toml_json "$R2b/.codex/config.toml" | jq -c '[.model, .mcp_servers.xcode.command, (.tui.status_line | length)]')" "a new [tui] table goes after the repo's own tables"
bash "$T/uninstall.sh" --into "$R2b" > /dev/null 2>&1
cmp -s "$SB/codex-own.toml" "$R2b/.codex/config.toml" && pass "uninstall removes the [tui] table it added, exactly" \
  || { fail "uninstall left the Codex config changed"; diff "$SB/codex-own.toml" "$R2b/.codex/config.toml" >&2; }

echo "── entries the user edited after install"
R3="$(new_repo edited)"
bash "$T/install.sh" --into "$R3" > /dev/null 2>&1
jq '.statusLine.refreshInterval = 5' "$R3/.claude/settings.json" > "$SB/e.json" && mv "$SB/e.json" "$R3/.claude/settings.json"
sed -i.bak 's/"used-tokens"\]/"used-tokens", "git-branch"]/' "$R3/.codex/config.toml" && rm "$R3/.codex/config.toml.bak"
bash "$T/install.sh" --into "$R3" > "$SB/install3.out" 2>&1
assert_eq 0 "$?" "a reinstall over edited entries succeeds"
assert_eq 5 "$(jq '.statusLine.refreshInterval' "$R3/.claude/settings.json")" "the reinstall keeps the Claude edit"
assert_eq 6 "$(toml_json "$R3/.codex/config.toml" | jq '.tui.status_line | length')" "the reinstall keeps the Codex edit"
assert_contains "$SB/install3.out" "kept your edited setting statusLine in .claude/settings.json" "the reinstall names the kept Claude entry"
assert_contains "$SB/install3.out" "kept your edited setting tui.status_line in .codex/config.toml" "the reinstall names the kept Codex entry"
bash "$T/uninstall.sh" --into "$R3" > "$SB/uninstall3.out" 2>&1
assert_eq 5 "$(jq '.statusLine.refreshInterval' "$R3/.claude/settings.json")" "uninstall keeps the edited Claude entry"
assert_eq 6 "$(toml_json "$R3/.codex/config.toml" | jq '.tui.status_line | length')" "uninstall keeps the edited Codex entry"
assert_no_file "$R3/.qwen" "uninstall still removes the unedited Qwen entry and its file"

echo "── uninstall from the fresh repo"
bash "$T/uninstall.sh" --into "$R" > "$SB/uninstall.out" 2>&1
assert_eq 0 "$?" "uninstall succeeds"
for d in .claude .qwen .codex .astra; do assert_no_file "$R/$d" "$d is gone: it held only what astra put there"; done

echo "── RED controls"
refused_cleanly() { assert_no_file "$1/.astra" "$2: no files were placed"; }
R4="$(new_repo foreign)"; mkdir -p "$R4/.claude"
printf '%s\n' '{"statusLine":{"type":"command","command":"echo mine"}}' > "$R4/.claude/settings.json"
red "a repo's own Claude statusLine is never replaced" 65 "already sets statusLine" bash "$T/install.sh" --into "$R4"
assert_eq '{"statusLine":{"type":"command","command":"echo mine"}}' "$(jq -c . "$R4/.claude/settings.json")" "the refused install left the Claude settings alone"
refused_cleanly "$R4" "foreign statusLine"
R5="$(new_repo foreign-codex)"; mkdir -p "$R5/.codex"; printf '%s\n' '[tui]' 'status_line = ["model-name"]' > "$R5/.codex/config.toml"
red "a repo's own Codex status_line is never replaced" 65 "already sets tui.status_line" bash "$T/install.sh" --into "$R5"
assert_no_file "$R5/.claude" "the refused install wrote no Claude settings"
R6="$(new_repo dotted)"; mkdir -p "$R6/.codex"; printf '%s\n' 'tui.animations = false' > "$R6/.codex/config.toml"
red "a Codex [tui] set with dotted keys is never edited" 65 "with dotted keys" env ASTRA_FORCE=1 bash "$T/install.sh" --into "$R6"
assert_eq 'tui.animations = false' "$(cat "$R6/.codex/config.toml")" "the dotted-key config is untouched"
R7="$(new_repo multiline)"; mkdir -p "$R7/.codex"; printf '%s\n' '[tui]' 'status_line = [' '  "model-name",' ']' > "$R7/.codex/config.toml"
red "a Codex value on several lines is never edited" 65 "edit it by hand" env ASTRA_FORCE=1 bash "$T/install.sh" --into "$R7"
refused_cleanly "$R7" "multi-line value"
R8="$(new_repo badjson)"; mkdir -p "$R8/.qwen"; printf '{"oops":' > "$R8/.qwen/settings.json"
red "an unreadable settings.json is never rewritten" 65 "is unreadable" bash "$T/install.sh" --into "$R8"
assert_eq '{"oops":' "$(cat "$R8/.qwen/settings.json")" "the unreadable Qwen settings are untouched"
R9="$(new_repo badshape)"; mkdir -p "$R9/.qwen"; printf '%s\n' '{"ui":"compact"}' > "$R9/.qwen/settings.json"
red "a settings key of the wrong shape refuses before any file lands" 65 "ui is not an object" env ASTRA_FORCE=1 bash "$T/install.sh" --into "$R9"
refused_cleanly "$R9" "wrong shape"
red "install without --into" 64 "usage: --into <repo>" bash "$T/install.sh"

echo "── the plugin's own tests, on astra's copy"
need /usr/bin/python3 "xcode-select --install"
/usr/bin/python3 -I -m unittest discover -s "$T/claude-plugin/bin" > "$SB/plugin-tests.out" 2>&1
assert_eq 0 "$?" "the tally script's unit tests pass under the /usr/bin/python3 the plugin runs"
finish
