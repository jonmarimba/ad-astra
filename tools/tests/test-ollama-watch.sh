#!/usr/bin/env bash
# test-ollama-watch.sh — seed/diff/notify against the real script with a recorded library
# page (the href shape ollama.com/library actually serves) and a recording botline. The
# failed-fetch path must leave state untouched — wiping seen.txt on a bad fetch would
# re-alert the entire library next run.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
OW="$HERE/../ollama-watch/ollama-watch"

mkdir -p "$SB/bin"
cat > "$SB/lib_v1.html" <<'EOF'
<a href="/library/llama3.3"><span>Llama</span></a>
<a href="/library/tinyfish">tiny</a>
EOF
cat > "$SB/lib_v2.html" <<'EOF'
<a href="/library/llama3.3"><span>Llama</span></a>
<a href="/library/tinyfish">tiny</a>
<a href="/library/qwen3-ultra">new hotness</a>
<a href="/library/boringmodel">meh</a>
EOF
cat > "$SB/bin/curl" <<SHIM
#!/usr/bin/env bash
[ -f "$SB/fetch_down" ] && exit 7
cat "$SB/current.html"
SHIM
cat > "$SB/bin/botline" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SB/botline.log"
SHIM
chmod +x "$SB/bin/"*
export CURL_BIN="$SB/bin/curl" BOTLINE_BIN="$SB/bin/botline" OLLAMA_WATCH_HOME="$SB/ow-home"
: > "$SB/botline.log"

# ---- first run seeds silently ----
cp "$SB/lib_v1.html" "$SB/current.html"
assert_rc 0 "first run seeds" "$OW" check
assert_file "$OLLAMA_WATCH_HOME/seen.txt" "seen.txt seeded"
[ -s "$SB/botline.log" ] && fail "seeding run notified (it must not)" || pass "seeding run sent nothing"

# ---- new frontier model appears -> notify with the name; boring model stays silent ----
cp "$SB/lib_v2.html" "$SB/current.html"
assert_rc 0 "diff run succeeds" "$OW" check
assert_contains "$SB/botline.log" "qwen3-ultra" "frontier newcomer notified by name"
assert_not_contains "$SB/botline.log" "boringmodel" "non-frontier newcomer NOT notified"
grep -qxF "boringmodel" "$OLLAMA_WATCH_HOME/seen.txt" && pass "non-frontier newcomer still recorded as seen" || fail "boringmodel missing from seen.txt"

# ---- same library again -> no re-alert ----
lines="$(wc -l < "$SB/botline.log" | tr -d ' ')"
"$OW" check >/dev/null
assert_eq "$lines" "$(wc -l < "$SB/botline.log" | tr -d ' ')" "unchanged library re-alerted nothing"

# ---- RED controls: failed fetch must fail AND leave state untouched ----
cp "$OLLAMA_WATCH_HOME/seen.txt" "$SB/seen.before"
touch "$SB/fetch_down"
red "failed fetch must exit nonzero" 1 "fetch failed" "$OW" check
cmp -s "$SB/seen.before" "$OLLAMA_WATCH_HOME/seen.txt" && pass "failed fetch left seen.txt byte-identical" || fail "failed fetch MUTATED seen.txt (would re-alert the whole library)"
rm -f "$SB/fetch_down"
red "unknown subcommand must fail" 1 "usage: ollama-watch" "$OW" frobnicate

finish
