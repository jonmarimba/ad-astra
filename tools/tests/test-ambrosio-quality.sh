#!/usr/bin/env bash
# test-ambrosio-quality.sh — the two "actually find HOT models" fixes added 2026-08-14 after
# Nemotron-3-Nano passed every existing filter (reputable org, right size, real staff pick) and
# turned out to be dead weight: same architecture family, same size class, as the already-loaded
# and already-active Nemotron-3.5-Lightning. Neither of these existed before — "org is reputable
# and it fits" was treated as sufficient, which is finding models that exist, not hot ones.
#
# (1) Redundancy check: a reactive trending-scan candidate whose family prefix already matches
#     something loaded on the host must be skipped, not pulled — checked by absence in ssh.log.
# (2) A want-list entry bypasses the redundancy check entirely — an explicit ask is honored
#     regardless of what's already loaded, since Jonathan asked for it on purpose.
# (3) Downloads tiebreaker: HF's own `downloads` field (already in every search response,
#     previously read and ignored) breaks ties between same-org/same-quant candidates — the
#     higher-download repo must be the one that gets pulled.
#
# Real repos throughout, not fictional ones — resolve_mlx_url's size check (repo_gb) hits
# huggingface.co directly via Python's urllib, which the CURL_BIN shim below does NOT intercept
# (same as test-ambrosio.sh's own documented constraint). A made-up repo name 404s against the
# real API and gets silently treated as "unknown size, over cap" — found live building this file,
# the first version used fictional "-HIGHDL"/"-LOWDL" repo names and neither ever pulled.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
AMBROSIO="$HERE/../ambrosio/ambrosio"
need python3 "xcode-select --install"
curl -s --max-time 15 "https://huggingface.co/api/models/mlx-community/Meta-Llama-3.1-8B-Instruct-4bit" >/dev/null \
  || { fail "huggingface.co unreachable — the live size-check leg cannot run"; finish; exit 1; }

export AMBROSIO_HOME="$SB/ambrosio-home"; mkdir -p "$AMBROSIO_HOME"
export HOME="$SB/home"; mkdir -p "$HOME/.config/opencode" "$HOME/.qwen"
echo '{"provider":{"omniroute":{"options":{"baseURL":"http://localhost:20128/v1"},"models":{}}}}' > "$HOME/.config/opencode/opencode.jsonc"
echo '{}' > "$HOME/.qwen/settings.json"

cat > "$AMBROSIO_HOME/config" <<'EOF'
HOST="fakehost.test"
LMS_PORT="1234"
SSH_TARGET="fakehost.test"
WATCHLIST="qwen3 llama"
SIZE_CAP_GB="80"
OMNIROUTE_NODE="test-node"
LMS_BIN="~/.lmstudio/bin/lms"
LMS_FORMAT="--mlx"
MAX_PER_RUN="2"
MIN_PARAMS_B="7"
EOF

# ---- fixture: host already has a real Qwen3 family model loaded (real repo, matches
#      test-ambrosio.sh's own already-validated fixture) ----
echo '{"data":[{"id":"qwen3-30b-a3b-4bit"}]}' > "$SB/loaded.json"
echo '{"data":[{"id":"qwen3-30b-a3b-4bit"},{"id":"meta-llama-3.1-8b-instruct-4bit"}]}' > "$SB/loaded_after_pull.json"

# The trending scan surfaces three shapes:
#   Qwen3    — same family AND same version as what is loaded. Must skip.
#   Llama3.1 — a family absent from the host. Must pull.
#
# Two candidates, not three, because MAX_PER_RUN is 2: a third pullable candidate silently
# consumed a slot and made the download-choice assertions below fail for a reason that had
# nothing to do with downloads.
#
# The skip case is the dead weight the redundancy check exists for (Nemotron-3-Nano beside
# Nemotron-3.5-Lightning, 2026-08-14). The OPPOSITE case — a newer version of a loaded family,
# which this check used to suppress and which cost Jonathan the GLM-5.3 find on 2026-08-26 —
# is covered by test-ambrosio-version-gate.sh, where the gate itself is under test.
cat > "$SB/trending.json" <<'EOF'
[{"id":"qwen/Qwen3-30B-A3B-Instruct"},{"id":"meta-llama/Llama-3.1-8B"}]
EOF
# want-list explicitly asks for ANOTHER Qwen3 term too — must NOT be skipped despite the redundancy
cat > "$AMBROSIO_HOME/wantlist.txt" <<'EOF'
Qwen3-Coder-Next
EOF

# real search results — two real, same-org (mlx-community), same-quant-tier (4bit) repos for the
# same family, differing in downloads by two orders of magnitude (confirmed live, 2026-08-14):
# Meta-Llama-3.1-8B-Instruct-4bit (16,265 downloads) vs Meta-Llama-3.1-8B-4bit (173 downloads).
# Both real repos, both ~4.5GB (confirmed), both well within SIZE_CAP_GB=80.
cat > "$SB/search_llama.json" <<'EOF'
[
  {"id": "mlx-community/Meta-Llama-3.1-8B-4bit", "downloads": 173},
  {"id": "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit", "downloads": 16265}
]
EOF
# Qwen3.6 must be RESOLVABLE, or "was it pulled" measures the stub instead of the gate. The
# previous version of this file had no such route, so the old "Qwen3.6 was not pulled"
# assertion passed whether the redundancy check worked or not — an untested harness dressed
# as a passing test.
cat > "$SB/search_qwen36.json" <<'EOF'
[{"id": "mlx-community/Qwen3.6-35B-A3B-4bit"}]
EOF
cat > "$SB/search_qwen3-coder-next.json" <<'EOF'
[{"id": "mlx-community/Qwen3-Coder-Next-4bit"}]
EOF
echo '[]' > "$SB/search_empty.json"

mkdir -p "$SB/bin"
cat > "$SB/bin/curl" <<SHIM
#!/usr/bin/env bash
# routes by URL; repo_gb's live size-check calls (api/models/<id>?blobs=true) are NOT routed
# here at all — they go through Python's own urllib inside the piped python3 process, straight
# to the real huggingface.co, same as test-ambrosio.sh's documented behavior
printf '%s\n' "\$*" >> "$SB/curl-calls.log"
for a in "\$@"; do case "\$a" in
  *sort=trendingScore*) cat "$SB/trending.json"; exit 0 ;;
  *api/models?search=Llama-3.1*) cat "$SB/search_llama.json"; exit 0 ;;
  *api/models?search=Qwen3-Coder-Next*) cat "$SB/search_qwen3-coder-next.json"; exit 0 ;;
  *api/models?search=Qwen3.6*) cat "$SB/search_qwen36.json"; exit 0 ;;
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
: > "$SB/ssh.log"; : > "$SB/curl-calls.log"

out="$("$AMBROSIO" check 2>"$SB/check.err")"; rc=$?
assert_eq "0" "$rc" "check exits 0"

# ---- (1) redundancy: the trending-scan Qwen3.6 term must NOT pull — same family already loaded.
#      family_term() strips the size/quant tokens ("35B", "A3B") from the HF id's tail, so the
#      derived term is "Qwen3.6", not the literal HF id — confirmed live, not assumed. ----
assert_not_contains "$SB/ssh.log" "Qwen3-30B-A3B-Instruct" "same-version same-family candidate was skipped, not pulled"
# The candidate is recorded under its DERIVED FAMILY TERM, not its full repo id: family_term()
# strips the size, the active-params and the "Instruct" suffix, so "Qwen3-30B-A3B-Instruct"
# becomes "Qwen3". Asserting on the full id looked right and could never pass.
grep -qxF "Qwen3" "$AMBROSIO_HOME/seen.txt" && pass "redundant candidate marked seen under its family term (won't be re-evaluated forever)" || fail "redundant candidate not marked seen"

# ---- (2) want-list bypasses the redundancy check — explicit ask, same family, still pulls ----
assert_contains "$SB/ssh.log" "Qwen3-Coder-Next-4bit" "want-list entry pulled DESPITE sharing a family ('qwen') with what's already loaded — explicit ask overrides the redundancy check"

# ---- (3) downloads tiebreaker: same org, same quant, the higher-download repo must be the one
#      actually fetched, not just any one of them ----
assert_contains "$SB/ssh.log" "Meta-Llama-3.1-8B-Instruct-4bit" "higher-download candidate (16,265 downloads) was the one pulled"
assert_not_contains "$SB/ssh.log" "https://huggingface.co/mlx-community/Meta-Llama-3.1-8B-4bit " "lower-download candidate (173 downloads) was NOT the one pulled — proves downloads is actually driving the choice, not incidental"

finish
