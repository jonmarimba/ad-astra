#!/usr/bin/env bash
# test-qwen-routing.sh — prove the qwen CLI reaches a model through an OpenAI-compatible endpoint
# (OmniRoute, in production) using the credentials in its settings, non-interactively.
#
# Every assertion is by effect: the model must say the marker word back. An earlier version of
# this file asserted only "output was non-empty", and passed on nothing but ollama's ANSI spinner.
#
# It used to run against the live OmniRoute on localhost:20128 with the key from the real
# ~/.qwen/settings.json, so it could only pass on one machine. The behaviour worth holding is the
# CLI's, not the service's, so this runs the REAL qwen binary against a stub endpoint
# (tools/tests/stub_omniroute.py) with a sandbox HOME. The questions about the live service
# (does glm-5.2 serve, is hf/ still dead, does the catalog list what the doctrine names) are
# health checks of one deployment, not tests of this repo: tools/omniroute-health runs them.
#
# The suite carries its own RED control: ROUTE_EXPECT=NOPE_THIS_CANNOT_APPEAR must FAIL. MARKER is
# what we ask for and EXPECT is what we assert came back; they stay separate variables because
# changing MARKER alone proves nothing (the prompt asks for MARKER, so the model echoes it).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../tests/lib.sh"
need qwen "npm install -g @qwen-code/qwen-code"
need python3 "install python3"

MARKER="ROUTE_OK_7431"
EXPECT="${ROUTE_EXPECT:-$MARKER}"
MODEL="ollamacloud/stub-model"

export HOME="$SB/home"; mkdir -p "$HOME/.qwen"
# Sandboxing HOME is not enough: anything XDG-aware prefers these over $HOME.
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
python3 "$HERE/../tests/stub_omniroute.py" --port-file "$SB/port" --model "$MODEL" &
STUB_PID=$!
trap 'kill "$STUB_PID" 2>/dev/null; _lib_cleanup' EXIT
for _ in $(seq 1 30); do [ -s "$SB/port" ] && break; sleep 0.2; done
PORT="$(cat "$SB/port" 2>/dev/null)"
[ -n "$PORT" ] || { fail "stub endpoint never reported a port"; finish; exit 1; }

cat > "$HOME/.qwen/settings.json" <<EOF
{"\$version":4,"model":{"name":"$MODEL"},
 "modelProviders":{"openai":[{"id":"$MODEL","name":"stub","baseUrl":"http://127.0.0.1:$PORT/v1","envKey":"OMNIROUTE_API_KEY"}]},
 "security":{"auth":{"baseUrl":"http://127.0.0.1:$PORT/v1","selectedType":"openai","apiKey":"test-key"}}}
EOF
echo test-install > "$HOME/.qwen/installation_id"   # an install marker; without it qwen runs its first-run wizard
cd "$SB" || exit 1                                   # a clean cwd: a stray .mcp.json would raise a trust dialog
export OMNIROUTE_API_KEY=test-key

ask() { perl -e 'alarm shift; exec @ARGV' 90 qwen -m "$1" -p "Reply with exactly: $MARKER" 2>&1; }

echo "== qwen -p, non-interactive, through the endpoint =="
# The claim this file exists to hold up: `qwen -p` DOES load the credentials in .security.auth
# and reaches the endpoint without a TTY. It was once believed not to. It does.
QOUT="$(ask "$MODEL")"
if echo "$QOUT" | grep -q "$EXPECT"; then pass "qwen -p returned the marker (credentials load non-interactively)"
else fail "qwen -p did not return the marker :: $(echo "$QOUT" | grep -v '^Warning:' | head -c 200)"; fi

echo "== RED control: a model the endpoint does not serve =="
# If this came back carrying the marker the harness would be matching something other than a
# real completion, and every pass above would be worthless.
RED="$(ask "ollamacloud/definitely-not-a-real-model-$$")"
if echo "$RED" | grep -q "$EXPECT"; then fail "RED control PASSED: a nonexistent model returned the marker. The harness is broken."
else pass "RED control fails as it must (a model the endpoint does not serve is rejected)"; fi
echo "$RED" | grep -q "404" && pass "and the endpoint's 404 reaches the caller instead of a silent empty answer" \
  || fail "the rejection did not surface the endpoint's error: $(echo "$RED" | head -c 160)"

finish
