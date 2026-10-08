#!/usr/bin/env bash
# Verify serving-catalog discovery and delayed retirement through the shipped tool.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d -t omniroute-sync-catalog)
trap 'rc=$?; if [ $rc -eq 0 ]; then rm -rf "$work"; else echo "Test artifacts: $work" >&2; fi' EXIT
mkdir -p "$work/bin" "$work/state"
cat > "$work/qwen.json" <<'JSON'
{"security":{"auth":{"apiKey":"fixture"}},"modelProviders":{"openai":[{"id":"ollamacloud/glm-5.1","name":"GLM 5.1"}]}}
JSON
cat > "$work/opencode.jsonc" <<'JSON'
{"provider":{"omniroute":{"models":{"ollamacloud/glm-5.1": {"name":"GLM 5.1"}}}}}
JSON
cat > "$work/bin/omniroute" <<'SH'
#!/bin/bash
case "$*" in
  *get-api-models*) printf '%s\n' '{"models":[{"provider":"ollamacloud","fullModel":"ollamacloud/glm-5.1","name":"GLM 5.1","available":true},{"provider":"ollamacloud","fullModel":"ollamacloud/glm-5.2","name":"GLM 5.2","available":false}]}' ;;
  *get-api-v1-models*) printf '%s\n' '{"data":[{"id":"ollamacloud/glm-5.2","name":"GLM 5.2","context_length":1000000},{"id":"ollamacloud/glm-5.3","name":"ollamacloud/GLM 5.3","context_length":1000000},{"id":"ollamacloud/glm-5.2-high","name":"GLM 5.2 high"}]}' ;;
  *) exit 2 ;;
esac
SH
cat > "$work/bin/curl" <<'SH'
#!/bin/bash
args="$*"
case "$args" in
  *'/v1/models'*) printf '%s\n' '{"data":[{"id":"ollamacloud/glm-5.2","context_length":1000000},{"id":"ollamacloud/glm-5.3","context_length":1000000}]}' ;;
  *'ollamacloud/glm-5.1'*) printf '%s\n' '{"error":{"message":"model retired"}}' ;;
  *'ollamacloud/glm-5.2'*|*'ollamacloud/glm-5.3'*) printf '%s\n' '{"choices":[{"message":{"content":"PING"}}]}' ;;
  *) exit 2 ;;
esac
SH
chmod +x "$work/bin/omniroute" "$work/bin/curl"
export ASTRA_PATH="$work/bin:$PATH"
export OMNIROUTE_BASE="http://fixture.invalid"
export OMNIROUTE_BIN="$work/bin/omniroute"
export QWEN_SETTINGS="$work/qwen.json"
export OPENCODE_SETTINGS="$work/opencode.jsonc"
export OMNIROUTE_SYNC_STATE_DIR="$work/state"
"$here/../omniroute-model-sync/omniroute-model-sync" --prune > "$work/first.log"
jq -e '.modelProviders.openai | map(.id) | index("ollamacloud/glm-5.3")' "$work/qwen.json" >/dev/null
jq -e '.modelProviders.openai | map(.id) | index("ollamacloud/glm-5.2")' "$work/qwen.json" >/dev/null
jq -e '.modelProviders.openai | map(.id) | index("ollamacloud/glm-5.1")' "$work/qwen.json" >/dev/null
if jq -e '.modelProviders.openai | map(.id) | index("ollamacloud/glm-5.2-high")' "$work/qwen.json" >/dev/null; then
  echo 'Effort variant entered picker' >&2; exit 1
fi
python3 - "$work/state/prune-first-failed.tsv" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1]);s=p.read_text()
if 'ollamacloud/glm-5.1' not in s: raise SystemExit('First failure was not recorded')
if 'Ollama Cloud' in s: raise SystemExit('A display name entered the retirement ledger')
p.write_text(s.replace(str(int(time.time())),str(int(time.time())-90000)))
PY
"$here/../omniroute-model-sync/omniroute-model-sync" --prune > "$work/second.log"
if jq -e '.modelProviders.openai | map(.id) | index("ollamacloud/glm-5.1")' "$work/qwen.json" >/dev/null; then
  echo 'Retired 5.1 still in picker after second daily failure' >&2; exit 1
fi
jq -e '.modelProviders.openai | map(.id) | index("ollamacloud/glm-5.3")' "$work/qwen.json" >/dev/null
printf '%s\n' 'Catalog test passed: newer models added, effort alias skipped, older route retained then removed after a second failure.'
