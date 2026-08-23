#!/usr/bin/env bash
# test-ambrosio.sh — the whole delivery loop run for real: the shipped ambrosio script, a
# recorded HF-API payload poisoned with every filter class it must reject, a recording ssh, a
# sandboxed home, and a LIVE HF size check (repo_gb hits the real huggingface.co API for the
# fixture repo mlx-community/Qwen3-30B-A3B-4bit, 17.2GB when pinned on 2026-08-12). Network to
# huggingface.co is required and its absence is a loud FAIL, not a skip.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
AMBROSIO="$HERE/../ambrosio/ambrosio"
need python3 "xcode-select --install"
curl -s --max-time 15 "https://huggingface.co/api/models/mlx-community/Qwen3-30B-A3B-4bit" >/dev/null || { fail "huggingface.co unreachable — the live size-check leg cannot run"; finish; exit 1; }

# This file tests the LOCAL delivery loop. Ambrosio also runs two cloud surfaces
# (ollama-watch, omniroute-model-sync) which have their own suites and their own tests
# here in test-ambrosio-frontdoor.sh — stub them to no-ops so the silence assertions below
# keep meaning "the local loop said nothing" rather than accidentally covering the cloud half.
mkdir -p "$SB/stub"
printf '#!/bin/bash\nexit 0\n' > "$SB/stub/ollama-watch"; chmod +x "$SB/stub/ollama-watch"
printf '#!/bin/bash\nexit 0\n' > "$SB/stub/omniroute-model-sync"; chmod +x "$SB/stub/omniroute-model-sync"
export OLLAMA_WATCH_BIN="$SB/stub/ollama-watch"
export OMNIROUTE_SYNC_BIN="$SB/stub/omniroute-model-sync"

export AMBROSIO_HOME="$SB/ambrosio-home"; mkdir -p "$AMBROSIO_HOME"
export HOME="$SB/home"   # expose_model edits $HOME/.config/opencode + $HOME/.qwen
mkdir -p "$HOME/.config/opencode" "$HOME/.qwen"
cat > "$HOME/.config/opencode/opencode.jsonc" <<'EOF'
{
  "provider": {
    "omniroute": {
      "options": { "baseURL": "http://localhost:20128/v1" },
      "models": {
        "lms/existing-model": { "name": "existing" }
      }
    }
  }
}
EOF
echo '{"theme":"dark"}' > "$HOME/.qwen/settings.json"

cat > "$AMBROSIO_HOME/config" <<'EOF'
HOST="fakehost.test"
LMS_PORT="1234"
SSH_TARGET="fakehost.test"
WATCHLIST="glm kimi deepseek qwen3 nemotron"
SIZE_CAP_GB="80"
OMNIROUTE_NODE="test-node"
LMS_BIN="~/.lmstudio/bin/lms"
LMS_FORMAT="--mlx"
MAX_PER_RUN="2"
MIN_PARAMS_B="7"
EOF

# ---- recorded HF payloads. Trending is poisoned with one entry per filter class. ----
# GOOD #1:            qwen/Qwen3-30B-A3B            -> family term "Qwen3", must survive+pull
# GOOD #2:            zai-org/GLM-4.5-Air           -> term "GLM-4.5-Air", must pull too
#                     (two pulls in one run proves MAX_PER_RUN=2 really delivers 2 — the
#                      ssh-drains-stdin bug degraded it to 1 silently)
# junk (distill):     deepseek-ai/...-Distill-...   -> JUNK token, must be rejected
# unknown org:        randomdude/kimi-k3-awesome    -> not in REPUTABLE, must be rejected
# toy (<7B):          nvidia/Nemotron-Toy-3B        -> size floor, must be rejected
# off-watchlist:      microsoft/phi-5-mini          -> no watchlist word, must be rejected
# family dup:         qwen/Qwen3-32B                -> same family as good #1, deduped
# no-quant-yet:       moonshotai/Kimi-K3            -> survives filters; search returns nothing
cat > "$SB/trending.json" <<'EOF'
[
 {"id":"qwen/Qwen3-30B-A3B"},
 {"id":"zai-org/GLM-4.5-Air"},
 {"id":"deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"},
 {"id":"randomdude/kimi-k3-awesome"},
 {"id":"nvidia/Nemotron-Toy-3B"},
 {"id":"microsoft/phi-5-mini"},
 {"id":"qwen/Qwen3-32B"},
 {"id":"moonshotai/Kimi-K3"}
]
EOF
# search results for "Qwen3 mlx": junk + huge bf16 + the real 4bit repo (ranked best, fits cap)
cat > "$SB/search_qwen3.json" <<'EOF'
[
 {"id":"someguy/Qwen3-30B-A3B-distill-4bit"},
 {"id":"mlx-community/Qwen3-30B-A3B-bf16"},
 {"id":"mlx-community/Qwen3-30B-A3B-4bit"}
]
EOF
# search results for "GLM-4.5-Air mlx": one real repo (60.2GB live on 2026-08-12, under the cap)
cat > "$SB/search_glm.json" <<'EOF'
[
 {"id":"mlx-community/GLM-4.5-Air-4bit"}
]
EOF
echo '{"data":[{"id":"existing-model"}]}' > "$SB/loaded.json"
echo '{"data":[{"id":"existing-model"},{"id":"qwen3-30b-a3b-4bit"},{"id":"glm-4.5-air-4bit"}]}' > "$SB/loaded_after_pull.json"
echo '[]' > "$SB/search_empty.json"

# ---- transport shims, injected via the *_BIN seams ----
mkdir -p "$SB/bin"
cat > "$SB/bin/curl" <<SHIM
#!/usr/bin/env bash
# routes by URL; everything else (repo_gb's urllib) hits the live API
for a in "\$@"; do case "\$a" in
  *sort=trendingScore*) cat "$SB/trending.json"; exit 0 ;;
  *api/models?search=Qwen3*) cat "$SB/search_qwen3.json"; exit 0 ;;
  *api/models?search=GLM-4.5-Air*) cat "$SB/search_glm.json"; exit 0 ;;
  *api/models?search=*) cat "$SB/search_empty.json"; exit 0 ;;
  *fakehost.test*) [ -f "$SB/host_down" ] && exit 7; cat "$SB/loaded.json"; exit 0 ;;
esac; done
exit 1
SHIM
cat > "$SB/bin/ssh" <<SHIM
#!/usr/bin/env bash
# mirrors real ssh's stdin semantics: WITHOUT -n it consumes the caller's stdin (which is
# what catches a dropped \`ssh -n\` in ambrosio's read-loop — the remaining candidate lines
# get eaten and the 2nd pull vanishes); WITH -n it leaves stdin alone, like the real thing
wantstdin=1
for a in "\$@"; do [ "\$a" = "-n" ] && wantstdin=0; done
[ "\$wantstdin" -eq 1 ] && cat > /dev/null
printf '%s\n' "\$*" >> "$SB/ssh.log"
cp "$SB/loaded_after_pull.json" "$SB/loaded.json"   # the pull makes the models appear on the host
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
: > "$SB/ssh.log"; : > "$SB/botline.log"

# ---- candidate filtering (status leg): only the two survivors may appear ----
# family terms keep the HF repo's case: "Qwen3", "Kimi-K3"
st="$("$AMBROSIO" status 2>/dev/null)"
case "$st" in *Qwen3*) pass "good candidate (Qwen3 family) survived the filters";; *) fail "good candidate missing from status";; esac
case "$st" in *GLM-4.5-Air*) pass "second good candidate (GLM-4.5-Air) survived";; *) fail "GLM-4.5-Air missing from status";; esac
case "$st" in *Kimi-K3*) pass "Kimi-K3 (no size in name) survived the size floor";; *) fail "Kimi-K3 wrongly filtered";; esac
# probes are case-insensitive and use tokens that would actually SURFACE in a leaked family
# term (an org name like 'randomdude' is stripped from terms, so probing it proved nothing)
for bad in distill awesome toy mini; do
  printf '%s\n' "$st" | grep -qi -- "$bad" && fail "poisoned entry '$bad' leaked through the filters" || pass "poisoned entry '$bad' rejected"
done
n="$(printf '%s\n' "$st" | grep -ci "qwen3")"
assert_eq "1" "$n" "qwen3 family deduped to one candidate (Qwen3-32B folded in)"

# ---- full check leg: resolve -> live size check -> pull -> expose -> notify ----
out="$("$AMBROSIO" check 2>"$SB/check.err")"; rc=$?
assert_eq "0" "$rc" "check exits 0"
assert_empty "$out" "check stdout is empty (schd silence contract)"
assert_contains "$SB/ssh.log" 'https://huggingface.co/mlx-community/Qwen3-30B-A3B-4bit' "pull targeted the real 4bit repo (bf16 and distill outranked/rejected)"
assert_contains "$SB/ssh.log" 'https://huggingface.co/mlx-community/GLM-4.5-Air-4bit' "SECOND pull happened (MAX_PER_RUN=2 delivered 2 — ssh left the candidate stream alone)"
assert_contains "$SB/ssh.log" '--yes' "lms get ran non-interactive"
grep -qxF "Qwen3" "$AMBROSIO_HOME/seen.txt" && pass "delivered family recorded in seen.txt" || fail "Qwen3 not recorded in seen.txt"
grep -qi "kimi" "$AMBROSIO_HOME/seen.txt" && fail "Kimi-K3 wrongly marked seen (no repo exists yet — must retry next run)" || pass "Kimi-K3 left unseen for retry (no MLX repo yet)"
assert_contains "$HOME/.config/opencode/opencode.jsonc" 'lms/qwen3-30b-a3b-4bit' "first delivered model exposed in OpenCode picker"
assert_contains "$HOME/.config/opencode/opencode.jsonc" 'lms/glm-4.5-air-4bit' "second delivered model exposed in OpenCode picker"
assert_eq "lms/glm-4.5-air-4bit" "$(python3 -c "import json;print(json.load(open('$HOME/.qwen/settings.json'))['model']['name'])")" "qwen default = last exposed model"
assert_contains "$SB/botline.log" "Ambrosio served" "JS notified via botline"

# ---- RED control: second run must pull NOTHING (seen dedup) ----
lines_before="$(wc -l < "$SB/ssh.log" | tr -d ' ')"
"$AMBROSIO" check >/dev/null 2>&1
lines_after="$(wc -l < "$SB/ssh.log" | tr -d ' ')"
assert_eq "$lines_before" "$lines_after" "re-run pulled nothing (seen.txt dedup held)"

# ---- host-down gate: inert, exit 0, silent stdout ----
touch "$SB/host_down"
out="$("$AMBROSIO" check 2>/dev/null)"; rc=$?
assert_eq "0" "$rc" "host down: check exits 0 (gated, not an error)"
assert_empty "$out" "host down: stdout silent"

finish
