#!/usr/bin/env bash
# test-ambrosio-wantlist.sh — the durable want-list feature (added 2026-08-14, Jonathan: "make a
# list of models to get and wait until it shows up on the network"), run against the REAL shipped
# ambrosio script with the same sandboxed transport shims as test-ambrosio.sh (recording ssh,
# fake curl responses keyed by URL). Proves the want-list is not cosmetic: a term that ONLY
# exists in wantlist.txt (never in the trending payload) must still resolve, pull, and land in
# seen.txt — and it must win a MAX_PER_RUN slot over a trending candidate, since it's an explicit
# ask, not a maybe.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
AMBROSIO="$HERE/../ambrosio/ambrosio"
need python3 "xcode-select --install"

export AMBROSIO_HOME="$SB/ambrosio-home"; mkdir -p "$AMBROSIO_HOME"
export HOME="$SB/home"
mkdir -p "$HOME/.config/opencode" "$HOME/.qwen"
cat > "$HOME/.config/opencode/opencode.jsonc" <<'EOF'
{"provider":{"omniroute":{"options":{"baseURL":"http://localhost:20128/v1"},"models":{}}}}
EOF
echo '{}' > "$HOME/.qwen/settings.json"

cat > "$AMBROSIO_HOME/config" <<'EOF'
HOST="fakehost.test"
LMS_PORT="1234"
SSH_TARGET="fakehost.test"
WATCHLIST="glm kimi deepseek qwen3 nemotron"
SIZE_CAP_GB="80"
OMNIROUTE_NODE="test-node"
LMS_BIN="~/.lmstudio/bin/lms"
LMS_FORMAT="--mlx"
MAX_PER_RUN="1"
MIN_PARAMS_B="7"
EOF

# trending payload has ONE candidate — "GLM-4.5-Air" — that would normally consume the sole
# MAX_PER_RUN=1 slot. The want-list entry must be tried FIRST and win that slot instead, proving
# priority ordering, not just "the want-list is tried at all."
cat > "$SB/trending.json" <<'EOF'
[{"id":"zai-org/GLM-4.5-Air"}]
EOF
cat > "$SB/search_trendingonly.json" <<'EOF'
[{"id":"mlx-community/GLM-4.5-Air-4bit"}]
EOF
# the want-list-only term: never appears in trending.json at all
cat > "$SB/search_specialwant.json" <<'EOF'
[{"id":"mlx-community/Qwen3-30B-A3B-4bit"}]
EOF
echo '{"data":[]}' > "$SB/loaded.json"
echo '{"data":[{"id":"qwen3-30b-a3b-4bit"}]}' > "$SB/loaded_after_pull.json"
echo '[]' > "$SB/search_empty.json"

mkdir -p "$SB/bin"
cat > "$SB/bin/curl" <<SHIM
#!/usr/bin/env bash
# log every call's full argv — this is what the comment-line RED control below actually checks
# against (found by convocation review, 2026-08-14: the original version asserted against
# pull.log, which nothing here ever writes a search URL to — a tautology that would pass even if
# comment lines WERE being sent to HF as literal search terms).
printf '%s\n' "\$*" >> "$SB/curl-calls.log"
for a in "\$@"; do case "\$a" in
  *sort=trendingScore*) cat "$SB/trending.json"; exit 0 ;;
  *api/models?search=GLM-4.5-Air*) cat "$SB/search_trendingonly.json"; exit 0 ;;
  *api/models?search=Qwen3-30B-A3B*) cat "$SB/search_specialwant.json"; exit 0 ;;
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
# Only a PULL makes models appear. Matching every ssh call also matched ambrosio's probe
# asking the host whether a download is already running, which made candidates look
# already-installed and broke the pull assertions. Real ssh has no such side effect.
case "\$*" in *huggingface.co*) cp "$SB/loaded_after_pull.json" "$SB/loaded.json";; esac
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

# ---- first invocation auto-creates wantlist.txt — must not error, must be a real, editable file ----
"$AMBROSIO" status >/dev/null 2>&1
assert_file "$AMBROSIO_HOME/wantlist.txt" "wantlist.txt auto-created on first run"

# ---- write the want-list: a comment, a blank line, and the real term — proves comments/blanks
#      don't get treated as literal search terms (a RED risk: '#' passed to resolve_mlx_url
#      would 404 the HF search silently, not crash, so this needs a positive check, not just
#      "no error") ----
cat > "$AMBROSIO_HOME/wantlist.txt" <<'EOF'
# this is a comment, must be skipped

Qwen3-30B-A3B
EOF

# ---- status must show the want-list ----
st="$("$AMBROSIO" status 2>/dev/null)"
case "$st" in *Qwen3-30B-A3B*) pass "status shows the want-list entry";; *) fail "want-list entry missing from status output";; esac

# ---- the real check: want-list term must pull, and must win the ONLY MAX_PER_RUN=1 slot over
#      the trending candidate (which never appears in ssh.log if the priority ordering is real) ----
out="$("$AMBROSIO" check 2>"$SB/check.err")"; rc=$?
assert_eq "0" "$rc" "check exits 0 with a want-list entry present"
assert_contains "$SB/ssh.log" "https://huggingface.co/mlx-community/Qwen3-30B-A3B-4bit" "want-list-only term (never in trending.json) actually pulled"
assert_not_contains "$SB/ssh.log" "GLM-4.5-Air" "want-list entry consumed the sole MAX_PER_RUN slot — trending candidate did NOT pull this run (priority proven, not assumed)"
grep -qxF "Qwen3-30B-A3B" "$AMBROSIO_HOME/seen.txt" && pass "want-list delivery recorded in seen.txt" || fail "Qwen3-30B-A3B not recorded in seen.txt"

# ---- RED control: comment/blank lines in wantlist.txt must never reach resolve_mlx_url as a
#      literal search term — checked against the shim's own call log, not pull.log (pull.log
#      only ever receives curl's STDERR on a real failure; it was never going to contain a search
#      URL either way, which is exactly why this control was a tautology before the fix above) ----
assert_not_contains "$SB/curl-calls.log" "search=%23" "a '#' comment line was never sent to HF as a literal search term (url-encoded '#')"

# ---- second run: want-list entry already in seen.txt, so the NOW-unblocked trending candidate
#      gets its slot — proves the want-list doesn't permanently starve the trending scan, only
#      outranks it while still pending ----
out2="$("$AMBROSIO" check 2>/dev/null)"; rc2=$?
assert_eq "0" "$rc2" "second run exits 0"
assert_contains "$SB/ssh.log" "https://huggingface.co/mlx-community/GLM-4.5-Air-4bit" "once the want-list entry is satisfied, the trending candidate gets its slot on the next run"

finish
