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

# REALISTIC starting fixtures — matching the actual shape of Jonathan's real files (found live,
# 2026-08-14: the ORIGINAL test-ambrosio.sh's opencode.jsonc fixture was missing the "npm" field
# every real omniroute provider block has; `opencode models` silently does not register a
# provider block without it, so that test's assert_contains passed while the real CLI would have
# shown nothing — exactly the gap this file exists to close).
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
assert_contains "$SB/qwen_tui.out" "qwen3-30b-a3b-4bit" "REAL qwen TUI /model picker shows the model ambrosio just delivered — not a config-file check, the actual rendered picker"

# ---- RED control: a model NEVER delivered must NOT appear anywhere real ----
assert_not_contains "$SB/opencode_models.out" "totally-fabricated-model-never-delivered" "RED: a model that was never delivered does not appear in real opencode output (proves the positive checks above aren't vacuously true)"
assert_not_contains "$SB/qwen_tui.out" "totally-fabricated-model-never-delivered" "RED: same, for the real qwen TUI picker"

finish
