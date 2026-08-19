#!/usr/bin/env bash
# test-qwen-routing.sh — prove the qwen CLI reaches real models through OmniRoute.
#
# Every assertion here is by effect: the model must say the marker word back. An earlier
# version of this file asserted only "output was non-empty", and test 5 passed on nothing
# but ollama's ANSI spinner — a green tick for a command that had produced no answer at all.
# If you weaken a check back to "not empty", you have re-introduced that bug.
#
# The suite carries its own RED control (test 0). If a route that MUST fail comes back
# passing, the harness is lying and the whole run aborts rather than reporting success.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"

OMNIROUTE="${OMNIROUTE_BASE:-http://localhost:20128}"
# MARKER is what we ask the model to say. EXPECT is what we assert came back. They are the
# same by default and MUST stay separate variables, because that separation is the only valid
# way to prove this suite can go red. Changing MARKER alone proves nothing — the prompt asks
# for MARKER, so the model echoes whatever you put there and every check still passes. That
# false-negative was found on 2026-08-19 while auditing this very file. The real RED probe is:
#   ROUTE_EXPECT=NOPE_THIS_CANNOT_APPEAR bash test-qwen-routing.sh   # must FAIL, exit 1
MARKER="ROUTE_OK_7431"
EXPECT="${ROUTE_EXPECT:-$MARKER}"
# 300, not 16. GLM and DeepSeek emit `reasoning` tokens before any `content`, so a small cap
# returns an empty choice and OmniRoute reports "no usable choices" — which reads exactly like
# a dead model. Verified 2026-08-19: seven ollamacloud models looked dead at 16 and all served
# at 300. Test 6 below holds this fact to account so a future edit cannot quietly undo it.
MAXTOK=300
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  OK   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
die()  { echo "ABORT: $1" >&2; exit 2; }

command -v curl >/dev/null || die "curl not installed"
command -v jq   >/dev/null || die "jq not installed — brew install jq"
command -v qwen >/dev/null || die "qwen CLI not on PATH — the thing under test is absent"

KEY="$(jq -r '.security.auth.apiKey' "$HOME/.qwen/settings.json" 2>/dev/null)"
[ -n "$KEY" ] && [ "$KEY" != "null" ] || die "no OmniRoute key at .security.auth.apiKey in ~/.qwen/settings.json"

curl -sf -m 10 "$OMNIROUTE/v1/models" -H "Authorization: Bearer $KEY" >/dev/null \
  || die "OmniRoute not answering at $OMNIROUTE — start it with 'omniroute serve' before running this"

# One request through OmniRoute. Echoes the raw body so callers can assert on it.
route_says() {
  curl -s -m 150 "$OMNIROUTE/v1/chat/completions" \
    -H "Content-Type: application/json" -H "Authorization: Bearer $KEY" \
    -d "{\"model\":\"$1\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: $MARKER\"}],\"max_tokens\":${2:-$MAXTOK},\"stream\":false}"
}

echo "== RED control =="
# A model id that cannot possibly resolve. If this comes back carrying the marker, the harness
# is matching something other than a real completion and every OK below is worthless.
RED="$(route_says "ollamacloud/definitely-not-a-real-model-$$" 2>&1)"
if echo "$RED" | grep -q "$EXPECT"; then
  die "RED control PASSED — a nonexistent model returned the marker. The harness is broken; ignore any result from this run."
fi
ok "RED control fails as it must (nonexistent model rejected)"

echo
echo "== OmniRoute =="
R="$(route_says "ollamacloud/glm-5.2")"
if echo "$R" | grep -q "$EXPECT"; then
  ok "OmniRoute serves ollamacloud/glm-5.2"
else
  fail "OmniRoute did not return the marker for ollamacloud/glm-5.2 :: $(echo "$R" | jq -r '.error.message // .' 2>/dev/null | head -c 160)"
fi

echo
echo "== qwen CLI, non-interactive =="
# This is the claim the whole file exists to hold up: `qwen -p` DOES load the credentials in
# .security.auth. It was once believed not to. It does.
QOUT="$(timeout 180 qwen -m "ollamacloud/glm-5.2" -p "Reply with exactly: $MARKER" 2>&1)"
if echo "$QOUT" | grep -q "$EXPECT"; then
  ok "qwen -p returned the marker (credentials load fine non-interactively)"
else
  fail "qwen -p did not return the marker :: $(echo "$QOUT" | grep -v '^Warning:' | head -c 200)"
fi

echo
echo "== hf/ prefix is genuinely dead =="
# Doctrine tells convocation runners never to use hf/ ids. This proves why, and will go RED
# the day Jonathan adds a HuggingFace credential — at which point the doctrine needs updating,
# which is exactly the notification wanted.
HF="$(route_says "hf/zai-org/GLM-5.2")"
if echo "$HF" | grep -qi 'No active credentials for provider: huggingface'; then
  ok "hf/ ids still fail for want of a HuggingFace credential (doctrine's warning holds)"
elif echo "$HF" | grep -q "$EXPECT"; then
  fail "hf/ NOW WORKS — a HuggingFace credential was added. Update the convocation doctrine, which currently says hf/ will fail."
else
  fail "hf/ failed in an unexpected way :: $(echo "$HF" | jq -r '.error.message // .' 2>/dev/null | head -c 160)"
fi

echo
echo "== the small-max_tokens trap =="
# Same model, same prompt, tiny cap. It must come back WITHOUT the marker. That is not a bug
# in OmniRoute — it is reasoning tokens eating the budget — and anyone probing model health
# with a small cap will mislabel healthy models as dead. If this ever passes with the marker,
# the models stopped emitting reasoning first and the MAXTOK comment above is stale.
TINY="$(route_says "ollamacloud/glm-5.2" 16)"
if echo "$TINY" | grep -q "$EXPECT"; then
  fail "max_tokens=16 returned the marker — the reasoning-token explanation for MAXTOK=300 no longer holds; re-check the comment before trusting it"
else
  ok "max_tokens=16 yields no usable answer, as documented (do not probe health with a small cap)"
fi

echo
echo "== catalog sanity =="
# Two facts worth pinning. First: the doctrine names ollamacloud/glm-5.2 explicitly, so it must
# be listed. Second: serving and being listed are DIFFERENT — ollamacloud/deepseek-v4-pro answers
# real completions while being absent from /v1/models, so "not in the catalog" is not evidence
# that a route is dead, and nothing here should start treating it that way.
CATALOG="$(curl -s -m 10 "$OMNIROUTE/v1/models" -H "Authorization: Bearer $KEY" | jq -r '.data[].id')"
if echo "$CATALOG" | grep -qx 'ollamacloud/glm-5.2'; then
  ok "ollamacloud/glm-5.2 is in the catalog (the id the doctrine names)"
else
  fail "ollamacloud/glm-5.2 missing from the catalog — the doctrine names an id OmniRoute no longer lists"
fi
UNLISTED="$(route_says "ollamacloud/deepseek-v4-pro")"
if echo "$UNLISTED" | grep -q "$EXPECT"; then
  ok "unlisted id ollamacloud/deepseek-v4-pro still serves (catalog absence proves nothing)"
else
  fail "ollamacloud/deepseek-v4-pro no longer serves :: $(echo "$UNLISTED" | jq -r '.error.message // .' 2>/dev/null | head -c 160)"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
