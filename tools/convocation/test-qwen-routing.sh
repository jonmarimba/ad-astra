#!/usr/bin/env bash
# test-qwen-routing.sh — prove qwen CLI routes to ollama cloud models through omniroute.
# RED-capable: fails loudly on wrong model IDs, dead providers, or empty completions.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"

OMNIROUTE="http://localhost:20128"
PASS=0; FAIL=0; SKIP=0

ok()   { PASS=$((PASS+1)); echo "  OK  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
skip() { SKIP=$((SKIP+1)); echo "  SKIP $1"; }

# ---- prerequisite: omniroute is running ----
if ! curl -sf "$OMNIROUTE/v1/models" >/dev/null 2>&1; then
  echo "FAIL: omniroute not reachable at $OMNIROUTE" >&2; exit 1
fi
ok "omniroute reachable"

# ---- prerequisite: qwen CLI exists ----
if ! command -v qwen >/dev/null 2>&1; then
  echo "FAIL: qwen CLI not on PATH" >&2; exit 1
fi
ok "qwen CLI on PATH"

# ---- test 1: ollamacloud/glm-5.2 exists in the catalog ----
CATALOG=$(curl -sf "$OMNIROUTE/v1/models" | jq -r '.data[].id')
if echo "$CATALOG" | grep -qx 'ollamacloud/glm-5.2'; then
  ok "ollamacloud/glm-5.2 in catalog"
else
  fail "ollamacloud/glm-5.2 NOT in catalog — model IDs may have changed"
  echo "  available ollamacloud/ models:"
  echo "$CATALOG" | grep '^ollamacloud/' | sed 's/^/    /'
fi

# ---- test 2: curl through omniroute returns a real completion ----
RESP=$(curl -sf "$OMNIROUTE/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(jq -r '.security.auth.apiKey' ~/.qwen/settings.json)" \
  -d '{"model":"ollamacloud/glm-5.2","messages":[{"role":"user","content":"Reply with exactly the word PONG"}],"stream":false}' 2>&1)
if [ $? -ne 0 ]; then
  fail "curl to omniroute ollamacloud/glm-5.2 failed"
elif echo "$RESP" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
  CONTENT=$(echo "$RESP" | jq -r '.choices[0].message.content')
  if [ -n "$CONTENT" ] && [ "$CONTENT" != "null" ]; then
    ok "omniroute returned completion: $(echo "$CONTENT" | head -c 60)"
  else
    fail "omniroute returned empty content"
  fi
else
  fail "omniroute response missing .choices[0].message.content: $(echo "$RESP" | head -c 200)"
fi

# ---- test 3: qwen non-interactive with ollamacloud/ model ----
QOUT=$(qwen -m "ollamacloud/glm-5.2" -p "Reply with exactly the word PONG" 2>&1)
QRC=$?
# qwen prints warnings to stderr mixed with stdout; strip Warning lines
QCLEAN=$(echo "$QOUT" | grep -v '^Warning:' | grep -v '^$')
if [ $QRC -ne 0 ]; then
  fail "qwen -m ollamacloud/glm-5.2 exited $QRC"
  echo "  output: $(echo "$QOUT" | head -5)"
elif [ -z "$QCLEAN" ]; then
  fail "qwen returned empty output"
else
  ok "qwen non-interactive returned: $(echo "$QCLEAN" | head -c 60)"
fi

# ---- test 4: qwen non-interactive with direct ollama model ----
QOUT2=$(qwen -m "glm-5.2:cloud" -p "Reply with exactly the word PONG" 2>&1)
QRC2=$?
QCLEAN2=$(echo "$QOUT2" | grep -v '^Warning:' | grep -v '^$')
if [ $QRC2 -ne 0 ]; then
  fail "qwen -m glm-5.2:cloud exited $QRC2"
elif [ -z "$QCLEAN2" ]; then
  fail "qwen glm-5.2:cloud returned empty output"
else
  ok "qwen direct ollama returned: $(echo "$QCLEAN2" | head -c 60)"
fi

# ---- test 5: convene.sh's ollama path works ----
OOUT=$(timeout 30 ollama run glm-5.2:cloud "Reply with exactly the word PONG" 2>&1)
ORC=$?
if [ $ORC -ne 0 ]; then
  fail "ollama run glm-5.2:cloud exited $ORC"
elif [ -z "$OOUT" ]; then
  fail "ollama run returned empty"
else
  ok "ollama run direct: $(echo "$OOUT" | head -c 60)"
fi

# ---- summary ----
echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] || exit 1
