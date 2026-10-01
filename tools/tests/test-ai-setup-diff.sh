#!/usr/bin/env bash
# test-ai-setup-diff.sh — the comparison logic against a REAL fake remote: the ssh shim
# executes each remote command with bash under a different $HOME, so remote-side quoting is
# genuinely evaluated (this is the seam where '$HOME' once shipped single-quoted, never
# expanded remotely, and everything falsely read "ONLY LOCAL").
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ASD="$HERE/../ai-setup-diff/ai-setup-diff"

LOCAL="$SB/local-home"; REMOTE="$SB/remote-home"
mkdir -p "$LOCAL/.claude" "$LOCAL/.codex" "$LOCAL/.qwen" "$REMOTE/.claude" "$REMOTE/.codex"
echo '{"model":"opus"}'    > "$LOCAL/.claude/settings.json"
echo '{"model":"sonnet"}'  > "$REMOTE/.claude/settings.json"     # DIFFERS
echo 'model = "gpt"'       > "$LOCAL/.codex/config.toml"
echo 'model = "gpt"'       > "$REMOTE/.codex/config.toml"        # same
echo '{"thinking":"high"}' > "$LOCAL/.qwen/settings.json"        # ONLY LOCAL
echo '# global rules'      > "$REMOTE/.claude/CLAUDE.md"         # ONLY REMOTE

mkdir -p "$SB/bin"
cat > "$SB/bin/ssh" <<SHIM
#!/usr/bin/env bash
[ -f "$SB/host_down" ] && exit 255
# last argument is the remote command; evaluate it for real under the fake remote home
for cmd in "\$@"; do :; done
HOME="$REMOTE" bash -c "\$cmd"
SHIM
chmod +x "$SB/bin/ssh"
export SSH_BIN="$SB/bin/ssh"

out="$(HOME="$LOCAL" "$ASD" fake-remote.test 2>/dev/null)"
printf '%s\n' "$out" | grep -q "DIFFERS     : ~/.claude/settings.json" && pass "differing file reported DIFFERS" || fail "DIFFERS missing for .claude/settings.json"
printf '%s\n' "$out" | grep -q "same        : ~/.codex/config.toml" && pass "identical file reported same (remote \$HOME expanded — the old quoting bug reads this ONLY LOCAL)" || fail "same missing for .codex/config.toml (remote quoting regressed?)"
printf '%s\n' "$out" | grep -q "ONLY LOCAL  : ~/.qwen/settings.json" && pass "local-only file reported ONLY LOCAL" || fail "ONLY LOCAL missing"
printf '%s\n' "$out" | grep -q "ONLY REMOTE : ~/.claude/CLAUDE.md" && pass "remote-only file reported ONLY REMOTE" || fail "ONLY REMOTE missing"
printf '%s\n' "$out" | grep -q "sonnet" && pass "DIFFERS shows the actual diff body" || fail "diff body missing"

# ---- read-only claim: the run must not have touched either home ----
[ "$(cat "$LOCAL/.claude/settings.json")" = '{"model":"opus"}' ] && pass "local config untouched" || fail "local config MUTATED by a read-only tool"
[ "$(cat "$REMOTE/.claude/settings.json")" = '{"model":"sonnet"}' ] && pass "remote config untouched" || fail "remote config MUTATED by a read-only tool"

# ---- RED control: unreachable host must produce NO comparison lines ----
touch "$SB/host_down"
# ASD itself exits 0 on an unreachable host (it reports gracefully rather than erroring), so the
# guard under test is "no comparison line leaked", not the tool's own exit code. The bash -c body
# does that check itself and turns the result into a real rc+diagnostic pair for red().
red "unreachable host yields no DIFFERS/same output" 1 "no comparison lines emitted for unreachable host" \
  bash -c "out=\$(HOME='$LOCAL' '$ASD' fake-remote.test 2>/dev/null); if printf '%s' \"\$out\" | grep -qE 'DIFFERS|same '; then echo 'FAIL: comparison line found for an unreachable host'; exit 0; else echo 'no comparison lines emitted for unreachable host'; exit 1; fi"
out2="$(HOME="$LOCAL" "$ASD" fake-remote.test 2>/dev/null)"
printf '%s\n' "$out2" | grep -q "unreachable" && pass "unreachable host stated plainly" || fail "no unreachable notice"

finish
