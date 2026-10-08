#!/usr/bin/env bash
# TIER: slow — drives real tmux, qwen and opencode sessions with sleeps (about 12s); needs no live service or machine state
# test-model-list-parity.sh — omniroute-model-sync keeps qwen's and opencode's model pickers in step.
#
# Both tools are meant to be fed from OmniRoute's catalog as the one system of record, and a model in
# one picker but not the other is the drift that was found live on 2026-08-14 (opencode had
# ollamacloud/glm-5.2, qwen did not, because the catalog getter did not list it).
#
# This used to copy Jonathan's live ~/.qwen and ~/.config/opencode config and compare what the real
# pickers showed, so it could only pass on his machine and said nothing about the writer. Now it
# builds both configs from fixtures, runs the REAL omniroute-model-sync against a stub OmniRoute
# (tools/tests/stub_omniroute.py plus a stub `omniroute` CLI), and reads the result back through the
# REAL qwen /model picker and the REAL `opencode models`. The comparison is the same one: the
# ollamacloud/* and lms/* entries each tool shows must be the same set. Other entries (opencode's
# auto/* aliases, qwen's legacy bare-tag :cloud entries) are built-ins that were never meant to match.
#
# INCIDENT, 2026-08-14: an earlier version ran qwen's interactive picker directly against the real
# settings.json. Arrowing through the list (never Enter) and closing with Escape still left a
# different default model selected, because the picker applies the highlighted row live. Everything
# here runs against a sandbox HOME that is deleted on exit.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
need tmux "brew install tmux"
need opencode "npm install -g opencode-ai (or see opencode.ai)"
need qwen "npm install -g @qwen-code/qwen-code"
need python3 "xcode-select --install"
need jq "brew install jq"

export HOME="$SB/home"; mkdir -p "$HOME/.qwen" "$HOME/.config/opencode"
# Sandboxing HOME is not enough: opencode and qwen prefer XDG_* over $HOME when they are set.
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME

# ---- a stub OmniRoute: a catalog of two ollamacloud models, both serving ----
python3 "$HERE/stub_omniroute.py" --port-file "$SB/port" --model ollamacloud/alpha-model --model ollamacloud/beta-model &
STUB_PID=$!
trap 'kill "$STUB_PID" 2>/dev/null; tmux kill-session -t "model-parity-$$" 2>/dev/null; _lib_cleanup' EXIT
for _ in $(seq 1 30); do [ -s "$SB/port" ] && break; sleep 0.2; done
BASE="http://127.0.0.1:$(cat "$SB/port")"
mkdir -p "$SB/bin"
cat > "$SB/bin/omniroute" <<'EOF'
#!/usr/bin/env bash
# the stub CLI: omniroute --output json api models get-api-models (management) and get-api-v1-models (serving)
echo 'Loaded env from /nowhere'
case "$*" in
  *get-api-v1-models*) cat <<'JSON'
{"data":[
 {"id":"ollamacloud/alpha-model","name":"Alpha Model","context_length":1000000},
 {"id":"ollamacloud/beta-model","name":"Beta Model","context_length":1000000},
 {"id":"other/ignored","name":"Not Ollama"}]}
JSON
  ;;
  *get-api-models*) cat <<'JSON'
{"models":[
 {"provider":"ollamacloud","fullModel":"ollamacloud/alpha-model","name":"Alpha Model","available":true},
 {"provider":"ollamacloud","fullModel":"ollamacloud/beta-model","name":"Beta Model","available":true},
 {"provider":"other","fullModel":"other/ignored","name":"Not Ollama","available":true}]}
JSON
  ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$SB/bin/omniroute"

# ---- realistic starting fixtures: one pre-existing entry in each, the same id ----
cat > "$HOME/.qwen/settings.json" <<EOF
{"\$version":4,"model":{"name":"lms/pre-existing","baseUrl":"$BASE/v1"},
 "modelProviders":{"openai":[{"id":"lms/pre-existing","name":"pre-existing","baseUrl":"$BASE/v1","envKey":"OMNIROUTE_API_KEY"}]},
 "security":{"auth":{"baseUrl":"$BASE/v1","selectedType":"openai","apiKey":"test-key"}}}
EOF
cat > "$HOME/.config/opencode/opencode.jsonc" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "omniroute": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "OmniRoute",
      "options": { "baseURL": "$BASE/v1", "apiKey": "test-key" },
      "models": {
        "lms/pre-existing": { "name": "pre-existing" }
      }
    }
  }
}
EOF
echo test-install > "$HOME/.qwen/installation_id"   # without it qwen runs its first-run wizard

# ---- run the REAL sync, with the endpoint and CLI pointed at the stubs ----
sync_out="$(OMNIROUTE_BIN="$SB/bin/omniroute" OMNIROUTE_BASE="$BASE" OMNIROUTE_API_KEY=test-key \
  QWEN_SETTINGS="$HOME/.qwen/settings.json" OPENCODE_SETTINGS="$HOME/.config/opencode/opencode.jsonc" \
  bash "$HERE/../omniroute-model-sync/omniroute-model-sync" 2>&1)"; rc=$?
echo "$sync_out" > "$SB/sync.out"
assert_eq 0 "$rc" "omniroute-model-sync ran to completion against the stub"
assert_contains "$SB/sync.out" "added 2 to qwen, 2 to opencode" "it added both catalog models to both tools"
assert_contains "$HOME/.qwen/settings.json" "$BASE/v1" "an entry it wrote routes through the configured endpoint, not a hardcoded one"

# ---- the qwen picker: TUI-only, needs a live tmux session. Launched from a clean cwd (a real
#      .mcp.json in the launch directory throws an "Untrusted MCP server" dialog that swallows every
#      keystroke). Scrolls the WHOLE picker in both directions: the picker opens near the active
#      model, not at item 1, so item 1 needs an explicit scroll-to-top first. ----
CLEAN_CWD="$SB/cwd"; mkdir -p "$CLEAN_CWD"
SESSION="model-parity-$$"
tmux new-session -d -s "$SESSION" -x 220 -y 50 -c "$CLEAN_CWD" -e HOME="$HOME"
tmux send-keys -t "$SESSION" "qwen" Enter
sleep 4
tmux send-keys -t "$SESSION" "/model"
sleep 1
tmux send-keys -t "$SESSION" Enter
sleep 1
: > "$SB/qwen_full.out"
for _ in $(seq 1 40); do tmux send-keys -t "$SESSION" Up; sleep 0.05; done
for _ in $(seq 1 40); do
  tmux capture-pane -t "$SESSION" -p >> "$SB/qwen_full.out"
  tmux send-keys -t "$SESSION" Down
  sleep 0.1
done
tmux kill-session -t "$SESSION" 2>/dev/null
assert_nonempty "$(cat "$SB/qwen_full.out")" "qwen TUI capture is non-empty (the picker actually opened)"

# ---- opencode: scriptable, no TUI needed, same sandbox HOME ----
oc_out="$(cd "$SB" && with_timeout 15 opencode models 2>"$SB/opencode.err")"
echo "$oc_out" > "$SB/opencode_full.out"
assert_nonempty "$oc_out" "opencode models output is non-empty"

# ---- extract the comparable id sets from each tool's REAL output ----
python3 - "$SB/qwen_full.out" "$SB/opencode_full.out" "$SB/qwen_ids.txt" "$SB/opencode_ids.txt" <<'PYEOF'
import re, sys
qwen_capture, oc_capture, qwen_out, oc_out = sys.argv[1:5]

# qwen's picker renders list entries as "N. [openai] Display Name (real-id)" with the id in trailing
# parens, but the ACTIVE model (the "Runtime" slot) renders as "N. [openai] <real-id> (Runtime)", id
# BEFORE the parens. Missing the second shape was a real bug once: the active model was never counted.
qwen_ids = set()
text = open(qwen_capture, errors='replace').read()
for m in re.finditer(r'\(((?:ollamacloud|lms)/[^)]+)\)', text):
    qwen_ids.add(m.group(1))
for m in re.finditer(r'\[openai\]\s+((?:ollamacloud|lms)/\S+)\s+\(Runtime\)', text):
    qwen_ids.add(m.group(1))
open(qwen_out, 'w').write('\n'.join(sorted(qwen_ids)))

# opencode's `models` output is one "provider/model-id" per line
oc_ids = set()
for line in open(oc_capture, errors='replace'):
    line = line.strip()
    if line.startswith('omniroute/ollamacloud/') or line.startswith('omniroute/lms/'):
        oc_ids.add(line[len('omniroute/'):])
open(oc_out, 'w').write('\n'.join(sorted(oc_ids)))
PYEOF

# The exact set, not "non-empty": the pre-existing entry plus what the sync added.
want="$(printf 'lms/pre-existing\nollamacloud/alpha-model\nollamacloud/beta-model\n')"
assert_eq "$want" "$(cat "$SB/qwen_ids.txt")" "qwen's real picker shows exactly the pre-existing model plus both synced ones"
assert_eq "$want" "$(cat "$SB/opencode_ids.txt")" "opencode's real output shows exactly the same three"

# ---- the parity check itself: symmetric diff must be empty ----
only_qwen="$(comm -23 "$SB/qwen_ids.txt" "$SB/opencode_ids.txt")"
only_oc="$(comm -13 "$SB/qwen_ids.txt" "$SB/opencode_ids.txt")"
assert_empty "$only_qwen" "no model is in qwen's list but missing from opencode's"
assert_empty "$only_oc" "no model is in opencode's list but missing from qwen's"

# ---- RED control: the comparison must be able to fail on real drift. Drop one synced model from
#      opencode's set, as the 2026-08-14 incident did, and the diff must name it. ----
grep -vxF "ollamacloud/beta-model" "$SB/opencode_ids.txt" > "$SB/opencode_drifted.txt"
drift="$(comm -23 "$SB/qwen_ids.txt" "$SB/opencode_drifted.txt")"
assert_eq "ollamacloud/beta-model" "$drift" "RED: the parity diff names the model missing from one tool (it is not vacuously green)"

finish
