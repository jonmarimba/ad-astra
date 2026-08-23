#!/usr/bin/env bash
# test-ambrosio-frontdoor.sh — ambrosio is now the single front door for "is there a hot
# model I can play with." Jonathan, 2026-08-22: "Ambrosio shouldn't fail outright when the
# M5 isn't around — there's the whole ollama subscription to check on." His condition on
# the change was "just don't fuck it up, I'm tired of things stopping working."
#
# So the property under test is not "the code runs." It is: WITH THE M5 ASLEEP, the cloud
# surfaces still run, and if either one is missing, ambrosio SAYS SO ON STDOUT rather than
# quietly checking one fewer thing. A front door that silently stops watching a surface is
# worse than the three separate jobs it replaced.
#
# The two cloud tools are real separate binaries with their own suites; here they are
# stubbed at their injectable seams so this file tests ambrosio's orchestration only.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
AMBROSIO="$HERE/../ambrosio/ambrosio"
need python3 "xcode-select --install"

export AMBROSIO_HOME="$SB/ambrosio-home"; mkdir -p "$AMBROSIO_HOME"
export HOME="$SB/home"; mkdir -p "$HOME"

# Host is unreachable: CURL_BIN always fails, which is what host_up probes with.
mkdir -p "$SB/stub"
cat > "$SB/stub/curl" <<'EOF'
#!/bin/bash
exit 7
EOF
chmod +x "$SB/stub/curl"
export CURL_BIN="$SB/stub/curl"

cat > "$AMBROSIO_HOME/config" <<'EOF'
HOST="fakehost.test"
LMS_PORT="1234"
SSH_TARGET="fakehost.test"
WATCHLIST="glm kimi"
SIZE_CAP_GB="80"
OMNIROUTE_NODE="fake node"
LMS_BIN="lms"
LMS_FORMAT="--mlx"
MAX_PER_RUN="2"
MIN_PARAMS_B="7"
CLOUD="1"
EOF

# Recording stubs for the two cloud surfaces.
cat > "$SB/stub/ollama-watch" <<EOF
#!/bin/bash
echo "ollama-watch ran: \$*" >> "$SB/watch.calls"
exit 0
EOF
cat > "$SB/stub/omniroute-model-sync" <<EOF
#!/bin/bash
echo "sync ran" >> "$SB/sync.calls"
echo "omniroute-model-sync: getter returned 9 ollamacloud model(s)"
echo "omniroute-model-sync: added 0 to qwen, 0 to opencode"
exit 0
EOF
chmod +x "$SB/stub/ollama-watch" "$SB/stub/omniroute-model-sync"
export OLLAMA_WATCH_BIN="$SB/stub/ollama-watch"
export OMNIROUTE_SYNC_BIN="$SB/stub/omniroute-model-sync"

# ---- 1. M5 asleep: cloud surfaces STILL RUN. This is the whole point of the change.
out="$(bash "$AMBROSIO" check 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && pass "host down: exit 0" || fail "host down: exit $rc"
[ -f "$SB/watch.calls" ] && pass "host down: ollama-watch STILL RAN" || fail "host down: ollama-watch did not run — the old inert-gate behaviour is back"
[ -f "$SB/sync.calls" ] && pass "host down: omniroute-model-sync STILL RAN" || fail "host down: the cloud catalog sync did not run"
grep -q "check" "$SB/watch.calls" 2>/dev/null && pass "ollama-watch invoked with its check subcommand" || fail "ollama-watch invoked wrongly: $(cat "$SB/watch.calls" 2>/dev/null)"

# ---- 2. A clean cloud run stays SILENT on stdout (schd pokes on non-empty stdout).
if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
    pass "clean run is silent on stdout (schd contract held)"
else
    fail "clean run printed to stdout, which pokes the session for nothing: $out"
fi

# ---- 3. RED control for #2 — a sync that reports a real change MUST break the silence.
rm -f "$SB/watch.calls" "$SB/sync.calls"
cat > "$SB/stub/omniroute-model-sync" <<'EOF'
#!/bin/bash
echo "omniroute-model-sync: added 1 to qwen, 1 to opencode"
exit 0
EOF
chmod +x "$SB/stub/omniroute-model-sync"
out2="$(bash "$AMBROSIO" check 2>/dev/null)"
printf '%s' "$out2" | grep -q "added 1" \
    && pass "RED control: a real cloud change DOES reach stdout" \
    || fail "RED control: a cloud change was swallowed — silence would be a lie ($out2)"

# ---- 3b. ollama-watch's own no-op line must NOT poke, but anything else it says must.
rm -f "$SB/watch.calls" "$SB/sync.calls"
cat > "$SB/stub/omniroute-model-sync" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$SB/stub/ollama-watch" <<'EOF'
#!/bin/bash
echo "ollama-watch: no new frontier models"
exit 0
EOF
chmod +x "$SB/stub/omniroute-model-sync" "$SB/stub/ollama-watch"
outq="$(bash "$AMBROSIO" check 2>/dev/null)"
[ -z "$(printf '%s' "$outq" | tr -d '[:space:]')" ] \
    && pass "ollama-watch's no-op line does not poke" \
    || fail "the no-op line reached stdout and would poke every run: $outq"

cat > "$SB/stub/ollama-watch" <<'EOF'
#!/bin/bash
echo "ollama-watch: NEW frontier model: glm-6"
exit 0
EOF
chmod +x "$SB/stub/ollama-watch"
outr="$(bash "$AMBROSIO" check 2>/dev/null)"
printf '%s' "$outr" | grep -q "glm-6" \
    && pass "RED control: a real new model from ollama-watch DOES poke" \
    || fail "RED control: a real new model was filtered away with the no-op line ($outr)"

# ---- 4. A missing surface is LOUD on stdout, not a quiet skip.
rm -f "$SB/watch.calls" "$SB/sync.calls"
export OLLAMA_WATCH_BIN="$SB/stub/does-not-exist"
out3="$(bash "$AMBROSIO" check 2>/dev/null)"
printf '%s' "$out3" | grep -q "ollama-watch NOT FOUND" \
    && pass "missing surface is reported on stdout" \
    || fail "missing surface was skipped silently — the front door stopped watching and said nothing"
export OLLAMA_WATCH_BIN="$SB/stub/ollama-watch"

# ---- 5. A cloud tool that fails is reported, not swallowed.
cat > "$SB/stub/omniroute-model-sync" <<'EOF'
#!/bin/bash
echo "boom" >&2
exit 3
EOF
chmod +x "$SB/stub/omniroute-model-sync"
err="$(bash "$AMBROSIO" check 2>&1 >/dev/null)"
printf '%s' "$err" | grep -q "omniroute-model-sync exited 3" \
    && pass "a failing cloud tool is reported" \
    || fail "a failing cloud tool was swallowed: $err"

# ---- 6. CLOUD=0 turns the cloud half off, for anyone who wants the old behaviour.
rm -f "$SB/watch.calls" "$SB/sync.calls"
cat > "$SB/stub/omniroute-model-sync" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$SB/stub/omniroute-model-sync"
sed -i '' 's/^CLOUD="1"$/CLOUD="0"/' "$AMBROSIO_HOME/config"
bash "$AMBROSIO" check >/dev/null 2>&1
[ ! -f "$SB/watch.calls" ] && pass "CLOUD=0 skips the cloud surfaces" || fail "CLOUD=0 did not disable the cloud half"

finish
