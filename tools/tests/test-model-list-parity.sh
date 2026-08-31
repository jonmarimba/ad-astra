#!/usr/bin/env bash
# TIER: slow — 14s measured 2026-08-31; talks to live model endpoints
# test-model-list-parity.sh — runs the REAL, currently-installed qwen and opencode binaries
# against a THROWAWAY COPY of Jonathan's live config (never the real $HOME/.qwen or
# $HOME/.config/opencode — see the incident note below) and confirms the "ollamacloud/*" and
# "lms/*" entries each tool's real picker shows are the SAME set. Both tools are meant to be kept
# in sync from OmniRoute as the system of record (ambrosio's expose_model + omniroute-model-sync
# both write to BOTH files) — a model present in one and missing from the other is exactly the
# drift class found live, 2026-08-14: OpenCode had "ollamacloud/glm-5.2" (confirmed real via a
# live completion through it) that qwen didn't, because OmniRoute's own catalog getter doesn't
# list GLM 5.2 at all (only 5.1) — omniroute-model-sync trusts that getter, so it silently missed
# a model that was already real and already working in the other tool.
#
# INCIDENT, 2026-08-14: the first version of this test ran qwen's interactive /model picker
# directly against Jonathan's REAL settings.json to scroll through the whole list. Navigating
# with Down (never Enter) and closing with Escape still left a different model selected as the
# real active default afterward — qwen's picker applies the highlighted row live as you arrow
# through it, Escape does not revert it. That silently changed Jonathan's real default model.
# Fixed by copying the real config into $SB (this test's own throwaway sandbox) and running qwen
# against THAT — any further picker-selection side effects land on a copy that gets deleted when
# the test exits, never on the files anything else actually reads.
#
# Deliberately scoped to ollamacloud/* and lms/* — NOT the full list. Each tool also carries its
# own built-ins (opencode's `auto/*` routing aliases, `hf/*`, `lc/*`; qwen's legacy bare-tag
# `:cloud` entries predating omniroute-model-sync) that were never meant to match — comparing the
# full sets would flag permanent, expected differences as false positives, which is its own
# silent-noise failure mode (a real mismatch gets lost in expected ones).
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
need tmux "brew install tmux"
need opencode "npm install -g opencode-ai (or see opencode.ai)"
need qwen "npm install -g @qwen-code/qwen-code"
need python3 "xcode-select --install"

QWEN_SETTINGS_REAL="${QWEN_SETTINGS:-$HOME/.qwen/settings.json}"
OPENCODE_SETTINGS_REAL="${OPENCODE_SETTINGS:-$HOME/.config/opencode/opencode.jsonc}"
assert_file "$QWEN_SETTINGS_REAL" "qwen settings.json exists"
assert_file "$OPENCODE_SETTINGS_REAL" "opencode.jsonc exists"

# ---- throwaway copy: read the real files' CONTENT, never run an interactive picker against the
#      real ones directly (see incident note above) ----
HOME_REAL="$HOME"
export HOME="$SB/home"
mkdir -p "$HOME/.qwen" "$HOME/.config/opencode"
cp "$QWEN_SETTINGS_REAL" "$HOME/.qwen/settings.json"
cp "$OPENCODE_SETTINGS_REAL" "$HOME/.config/opencode/opencode.jsonc"
[ -f "$HOME_REAL/.qwen/installation_id" ] && cp "$HOME_REAL/.qwen/installation_id" "$HOME/.qwen/installation_id" 2>/dev/null || true

# ---- copy's qwen picker: TUI-only, needs a live tmux session. Launched from a clean cwd — a real
#      .mcp.json in the launch directory throws an "Untrusted MCP server" dialog that swallows
#      every keystroke sent after it (found live, 2026-08-14). Scrolls the WHOLE picker in both
#      directions — a real list this size doesn't fit one viewport, and the picker opens scrolled
#      to wherever the CURRENTLY ACTIVE model sits, not to item 1, so item 1 needs an explicit
#      scroll-to-top first or it's silently never captured. ----
CLEAN_CWD="$SB/cwd"; mkdir -p "$CLEAN_CWD"
SESSION="model-parity-qwen-$$"
tmux kill-session -t "$SESSION" 2>/dev/null
tmux new-session -d -s "$SESSION" -x 220 -y 50 -c "$CLEAN_CWD" -e HOME="$HOME"
tmux send-keys -t "$SESSION" "qwen" Enter
sleep 4
tmux send-keys -t "$SESSION" "/model"
sleep 1
tmux send-keys -t "$SESSION" Enter
sleep 1
: > "$SB/qwen_full.out"
# scroll all the way to the top first — the picker opens positioned near the active model, which
# can be anywhere in the list, not at item 1
for _ in $(seq 1 40); do tmux send-keys -t "$SESSION" Up; sleep 0.05; done
# then walk all the way down, capturing every screen so no entry is missed to a viewport that
# never showed it (harmless to keep pressing Down once already at the bottom)
for _ in $(seq 1 40); do
  tmux capture-pane -t "$SESSION" -p >> "$SB/qwen_full.out"
  tmux send-keys -t "$SESSION" Down
  sleep 0.1
done
tmux kill-session -t "$SESSION" 2>/dev/null   # kill outright — no Escape/quit needed, this is a
# throwaway copy; whatever got selected while scrolling doesn't matter
assert_nonempty "$(cat "$SB/qwen_full.out")" "qwen TUI capture (against a throwaway copy of the real config) is non-empty (picker actually opened)"

# ---- copy's opencode: scriptable, no TUI needed, same throwaway HOME as the qwen leg above so
#      both tools are compared against the exact same snapshot ----
oc_out="$(cd "$SB" && HOME="$HOME" timeout 15 opencode models 2>"$SB/opencode.err")"
echo "$oc_out" > "$SB/opencode_full.out"
assert_nonempty "$oc_out" "opencode models output (against the same throwaway copy) is non-empty"

export HOME="$HOME_REAL"   # restore for anything after this point in the file

# ---- extract the comparable id sets from each tool's REAL output ----
python3 - "$SB/qwen_full.out" "$SB/opencode_full.out" "$SB/qwen_ids.txt" "$SB/opencode_ids.txt" <<'PYEOF'
import re, sys
qwen_capture, oc_capture, qwen_out, oc_out = sys.argv[1:5]

# qwen's picker renders list entries as "N. [openai] Display Name (real-id)" — id in the trailing
# parens — but the currently-ACTIVE model (item 1, the "Runtime" slot) renders differently:
# "N. [openai] <real-id> (Runtime)", id BEFORE the parens, "Runtime" inside them. Missing this
# second shape was a real bug in the first version of this file — the active model was silently
# never counted at all.
qwen_ids = set()
text = open(qwen_capture, errors='replace').read()
for m in re.finditer(r'\(((?:ollamacloud|lms)/[^)]+|[a-z0-9._-]+:cloud|ollamacloud[^)]*)\)', text):
    val = m.group(1)
    if val.startswith('ollamacloud/') or val.startswith('lms/'):
        qwen_ids.add(val)
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

qwen_count="$(grep -c . "$SB/qwen_ids.txt" 2>/dev/null || echo 0)"
oc_count="$(grep -c . "$SB/opencode_ids.txt" 2>/dev/null || echo 0)"
assert_nonempty "$qwen_count" "qwen ollamacloud/lms id set was extracted"
[ "$qwen_count" -gt 0 ] && pass "qwen has $qwen_count ollamacloud/lms entries in its real picker" || fail "qwen shows ZERO ollamacloud/lms entries — extraction broken or config regressed"
[ "$oc_count" -gt 0 ] && pass "opencode has $oc_count ollamacloud/lms entries in its real output" || fail "opencode shows ZERO ollamacloud/lms entries — extraction broken or config regressed"

# ---- the actual parity check: symmetric diff must be empty ----
only_qwen="$(comm -23 "$SB/qwen_ids.txt" "$SB/opencode_ids.txt")"
only_oc="$(comm -13 "$SB/qwen_ids.txt" "$SB/opencode_ids.txt")"

if [ -z "$only_qwen" ]; then
  pass "no model is in qwen's real list but missing from opencode's"
else
  fail "in qwen but missing from opencode: $(printf '%s' "$only_qwen" | tr '\n' ' ')"
fi
if [ -z "$only_oc" ]; then
  pass "no model is in opencode's real list but missing from qwen's"
else
  fail "in opencode but missing from qwen: $(printf '%s' "$only_oc" | tr '\n' ' ')"
fi

# ---- RED control: the comparison itself must be able to fail — prove it by diffing the qwen
#      set against itself minus one real entry, not a fabricated name ----
one_real="$(head -1 "$SB/qwen_ids.txt")"
if [ -n "$one_real" ]; then
  grep -vxF "$one_real" "$SB/qwen_ids.txt" > "$SB/qwen_ids_minus_one.txt"
  missing="$(comm -23 "$SB/qwen_ids.txt" "$SB/qwen_ids_minus_one.txt")"
  assert_eq "$one_real" "$missing" "RED: the comm-based diff genuinely detects a real, single removed entry (proves the parity check above isn't vacuously green)"
else
  fail "RED control skipped — qwen_ids.txt was empty, which the earlier assertion should already have failed loudly on"
fi

finish
