#!/usr/bin/env bash
# test-ambrosio-tui.sh — proves a model ambrosio delivers actually shows up in the REAL qwen and
# OpenCode TUIs, not just that expose_model() wrote plausible-looking text into their config
# files. Jonathan's explicit ask (2026-08-14): "actual tests. Like checking qwen and open code
# have the right list in their TUIs" — a passing assert_contains on the config file is not that;
# a wrong or incomplete config (see the RED control below) can still "contain" the right text
# while the real CLI fails to register it at all.
#
# Runs the REAL ambrosio through a full sandboxed check (recorded transport, same real-repo
# fixture as test-ambrosio.sh — mlx-community/Qwen3-30B-A3B-4bit, so the live HF size-check leg
# is real, not faked), then launches the REAL qwen and opencode binaries against the sandbox
# expose_model wrote into, and reads their ACTUAL output — qwen via a real tmux session (its
# model list is TUI-only, no headless query), opencode via its own `opencode models` command
# (genuinely scriptable, no TUI needed there).
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
AMBROSIO="$HERE/../ambrosio/ambrosio"
need python3 "xcode-select --install"
need tmux "brew install tmux"
need opencode "npm install -g opencode-ai (or see opencode.ai)"
need qwen "npm install -g @qwen-code/qwen-code"
curl -s --max-time 15 "https://huggingface.co/api/models/mlx-community/Qwen3-30B-A3B-4bit" >/dev/null \
  || { fail "huggingface.co unreachable — the live size-check leg cannot run"; finish; exit 1; }

HOME_REAL="$HOME"
export AMBROSIO_HOME="$SB/ambrosio-home"; mkdir -p "$AMBROSIO_HOME"
export HOME="$SB/home"; mkdir -p "$HOME/.config/opencode" "$HOME/.qwen"
CLEAN_CWD="$SB/cwd"; mkdir -p "$CLEAN_CWD"   # no .mcp.json here — a real one in cwd throws an
# "Untrusted MCP server" approval dialog that swallows every keystroke sent after it, including
# /model (found live, 2026-08-14, launching qwen from this repo's own root by accident)

# REALISTIC starting fixtures — matching the actual shape of Jonathan's real files. (Correction,
# 2026-08-14: an earlier version of this comment claimed `opencode models` needs the "npm" field
# to register a provider's entries — that was an unverified inference from an earlier debug
# session that changed two things at once (an empty models map AND the missing npm field) and
# blamed the wrong one. Tested each in isolation afterward: npm absent + a real model entry still
# shows up fine; an EMPTY models map is what actually produces nothing. The RED control below
# tests the real variable, not the wrong one.)
cat > "$HOME/.config/opencode/opencode.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "omniroute": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "OmniRoute",
      "options": { "baseURL": "http://localhost:20128/v1", "apiKey": "test-key" },
      "models": {
        "lms/pre-existing-model": { "name": "pre-existing" }
      }
    }
  }
}
EOF
cat > "$HOME/.qwen/settings.json" <<'EOF'
{
  "$version": 4,
  "model": { "name": "pre-existing-default", "baseUrl": "http://localhost:20128/v1" },
  "modelProviders": { "openai": [ { "id": "pre-existing-default", "name": "pre-existing" } ] },
  "security": {
    "auth": { "baseUrl": "http://localhost:20128/v1", "selectedType": "openai", "apiKey": "test-key" }
  },
  "selectedProvider": "omniroute"
}
EOF
# qwen needs installation_id to skip its own first-run setup wizard (found live, 2026-08-14 —
# without it the real TUI shows an onboarding flow instead of ever reaching the prompt at all).
# Not a secret, just an install marker — safe to copy from the real ~/.qwen if present.
[ -f "$HOME_REAL/.qwen/installation_id" ] 2>/dev/null && cp "$HOME_REAL/.qwen/installation_id" "$HOME/.qwen/installation_id" 2>/dev/null || true

cat > "$AMBROSIO_HOME/config" <<'EOF'
HOST="fakehost.test"
LMS_PORT="1234"
SSH_TARGET="fakehost.test"
WATCHLIST="qwen3"
SIZE_CAP_GB="80"
OMNIROUTE_NODE="test-node"
LMS_BIN="~/.lmstudio/bin/lms"
LMS_FORMAT="--mlx"
MAX_PER_RUN="1"
MIN_PARAMS_B="7"
EOF

cat > "$SB/trending.json" <<'EOF'
[{"id":"qwen/Qwen3-30B-A3B"}]
EOF
cat > "$SB/search_qwen3.json" <<'EOF'
[{"id":"mlx-community/Qwen3-30B-A3B-4bit"}]
EOF
echo '{"data":[]}' > "$SB/loaded.json"
echo '{"data":[{"id":"qwen3-30b-a3b-4bit"}]}' > "$SB/loaded_after_pull.json"
echo '[]' > "$SB/search_empty.json"

mkdir -p "$SB/bin"
cat > "$SB/bin/curl" <<SHIM
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in
  *sort=trendingScore*) cat "$SB/trending.json"; exit 0 ;;
  *api/models?search=Qwen3*) cat "$SB/search_qwen3.json"; exit 0 ;;
  *api/models?search=*) cat "$SB/search_empty.json"; exit 0 ;;
  *fakehost.test*) cat "$SB/loaded.json"; exit 0 ;;
esac; done
exit 1
SHIM
cat > "$SB/bin/ssh" <<SHIM
#!/usr/bin/env bash
wantstdin=1
for a in "\$@"; do [ "\$a" = "-n" ] && wantstdin=0; done
[ "\$wantstdin" -eq 1 ] && cat > /dev/null
printf '%s\n' "\$*" >> "$SB/ssh.log"
cp "$SB/loaded_after_pull.json" "$SB/loaded.json"
exit 0
SHIM
cat > "$SB/bin/botline" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SB/botline.log"
SHIM
cat > "$SB/bin/omniroute" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SB/omniroute.log"
SHIM
chmod +x "$SB/bin/"*
export CURL_BIN="$SB/bin/curl" SSH_BIN="$SB/bin/ssh" OMNIROUTE_BIN="$SB/bin/omniroute" BOTLINE_BIN="$SB/bin/botline"
: > "$SB/ssh.log"

# ---- run the real delivery ----
"$AMBROSIO" check >/dev/null 2>"$SB/check.err"
assert_contains "$SB/ssh.log" "Qwen3-30B-A3B-4bit" "sandboxed ambrosio actually delivered the fixture model (setup sanity check before the real-CLI assertions below)"

# ---- REAL opencode: scriptable, no TUI needed ----
oc_out="$(cd "$SB" && HOME="$HOME" timeout 15 opencode models 2>"$SB/opencode.err")"
echo "$oc_out" > "$SB/opencode_models.out"
assert_contains "$SB/opencode_models.out" "omniroute/lms/qwen3-30b-a3b-4bit" "REAL opencode CLI (not the config file) lists the delivered model — opencode models"
assert_contains "$SB/opencode_models.out" "omniroute/lms/pre-existing-model" "REAL opencode CLI still lists the pre-existing model too (delivery is additive, not destructive)"

# ---- REAL qwen: TUI-only, needs a live tmux session ----
SESSION="ambrosio-tui-test-$$"
tmux kill-session -t "$SESSION" 2>/dev/null
tmux new-session -d -s "$SESSION" -x 200 -y 50 -c "$CLEAN_CWD" -e HOME="$HOME"
tmux send-keys -t "$SESSION" "qwen" Enter
sleep 4
tmux send-keys -t "$SESSION" "/model"
sleep 1
tmux send-keys -t "$SESSION" Enter
sleep 2
tmux capture-pane -t "$SESSION" -p > "$SB/qwen_tui.out"
tmux send-keys -t "$SESSION" "/quit" Enter 2>/dev/null
sleep 1
tmux kill-session -t "$SESSION" 2>/dev/null

assert_contains "$SB/qwen_tui.out" "pre-existing-default" "REAL qwen TUI /model picker shows the pre-existing entry (sanity: the picker actually opened against the sandboxed HOME)"
# expose_model only ever replaces the top-level `model` field, never appends to modelProviders —
# so the delivered model surfaces as the active/Runtime slot the picker renders at item 1, not as
# a second, independent list entry. The string genuinely appears in the real rendered picker
# (RED-capable — deleting expose_model's `d['model']={...}` assignment makes it vanish, verified
# live), the label just used to overclaim which part of the UI that proves.
assert_contains "$SB/qwen_tui.out" "qwen3-30b-a3b-4bit" "REAL qwen TUI shows the delivered model as the active/Runtime slot in the real rendered /model picker — not a config-file check"

# ---- RED control: prove the positive checks above are load-bearing, not vacuous. A fabricated
#      name being absent proves nothing (nothing could ever make it present) — found by
#      convocation review, 2026-08-14, and it was right: the two checks that used to be here were
#      tautologies, always green regardless of whether the real checks above meant anything.
#
#      The real RED case is a HOME the delivery never touched: same config shape as the ORIGINAL
#      pre-ambrosio fixture, minus the model this run delivered. If the positive checks above
#      would pass against this too, they were never actually reading real output. (An earlier
#      version of this control instead removed the "npm" field, based on a wrong inference from
#      an earlier debug session — tested in isolation afterward, npm turned out not to matter at
#      all; an EMPTY models map is what actually produces no output. Fixed to test the real
#      variable — see the fixture comment above.) ----
NEVER_DELIVERED_HOME="$SB/home-never-delivered"; mkdir -p "$NEVER_DELIVERED_HOME/.config/opencode" "$NEVER_DELIVERED_HOME/.qwen"
cat > "$NEVER_DELIVERED_HOME/.config/opencode/opencode.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "omniroute": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "OmniRoute",
      "options": { "baseURL": "http://localhost:20128/v1", "apiKey": "test-key" },
      "models": { "lms/pre-existing-model": { "name": "pre-existing" } }
    }
  }
}
EOF
never_out="$(cd "$SB" && HOME="$NEVER_DELIVERED_HOME" timeout 15 opencode models 2>/dev/null)"
printf '%s' "$never_out" > "$SB/opencode_models_never_delivered.out"
assert_not_contains "$SB/opencode_models_never_delivered.out" "qwen3-30b-a3b-4bit" "RED, proven not assumed: a HOME the delivery never touched does not show the delivered model in real opencode output — confirms the positive check above is reading something real, not passing regardless"

# same RED case, qwen side — same never-delivered HOME shape, a real tmux session, real capture
mkdir -p "$NEVER_DELIVERED_HOME/.qwen"
cat > "$NEVER_DELIVERED_HOME/.qwen/settings.json" <<'EOF'
{
  "$version": 4,
  "model": { "name": "pre-existing-default", "baseUrl": "http://localhost:20128/v1" },
  "modelProviders": { "openai": [ { "id": "pre-existing-default", "name": "pre-existing" } ] },
  "security": {
    "auth": { "baseUrl": "http://localhost:20128/v1", "selectedType": "openai", "apiKey": "test-key" }
  },
  "selectedProvider": "omniroute"
}
EOF
[ -f "$HOME_REAL/.qwen/installation_id" ] 2>/dev/null && cp "$HOME_REAL/.qwen/installation_id" "$NEVER_DELIVERED_HOME/.qwen/installation_id" 2>/dev/null || true
NEVER_SESSION="ambrosio-tui-never-$$"
tmux kill-session -t "$NEVER_SESSION" 2>/dev/null
tmux new-session -d -s "$NEVER_SESSION" -x 200 -y 50 -c "$CLEAN_CWD" -e HOME="$NEVER_DELIVERED_HOME"
tmux send-keys -t "$NEVER_SESSION" "qwen" Enter
sleep 4
tmux send-keys -t "$NEVER_SESSION" "/model"
sleep 1
tmux send-keys -t "$NEVER_SESSION" Enter
sleep 2
tmux capture-pane -t "$NEVER_SESSION" -p > "$SB/qwen_tui_never_delivered.out"
tmux send-keys -t "$NEVER_SESSION" "/quit" Enter 2>/dev/null
sleep 1
tmux kill-session -t "$NEVER_SESSION" 2>/dev/null
assert_contains "$SB/qwen_tui_never_delivered.out" "pre-existing-default" "sanity: the never-delivered qwen picker still opened for real (same rigor as the primary sanity check above)"
assert_not_contains "$SB/qwen_tui_never_delivered.out" "qwen3-30b-a3b-4bit" "RED, proven not assumed: same never-delivered HOME, real qwen TUI — delivered model does not appear, confirms the qwen positive check is reading something real"

finish
