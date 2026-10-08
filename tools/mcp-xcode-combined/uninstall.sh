#!/usr/bin/env bash
# astra-scope: repo-config
# mcp-xcode-combined — remove the aggregator entry install.sh wrote into a repo.
#
# Removes ONLY the "xcode-combined" server: from <repo>/.mcp.json (the file itself goes
# away when that was its only content) and its [mcp_servers.xcode-combined] table from
# <repo>/.codex/config.toml. Every other server's entry is left exactly as it was. It
# never stops the aggregator daemon: that is machine-level, shared by every repo.
#
# Usage: ./uninstall.sh --into <repo>
set -uo pipefail
NAME="xcode-combined"

TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="${2:-}"; shift 2 ;;
    *) echo "mcp-xcode-combined: unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: uninstall.sh --into <repo>" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "mcp-xcode-combined: no such directory: $TARGET" >&2; exit 66; }
command -v jq >/dev/null || { echo "mcp-xcode-combined: FAIL — jq missing. brew install jq" >&2; exit 69; }

MCPJSON="$TARGET/.mcp.json"
if [ -f "$MCPJSON" ] && jq -e --arg n "$NAME" '.mcpServers[$n]' "$MCPJSON" >/dev/null 2>&1; then
  tmp="$(mktemp)"
  jq --arg n "$NAME" 'del(.mcpServers[$n])' "$MCPJSON" > "$tmp" \
    || { rm -f "$tmp"; echo "mcp-xcode-combined: FAIL — $MCPJSON is not valid JSON; fix it by hand." >&2; exit 65; }
  if jq -e '(.mcpServers // {} | length) == 0 and (del(.mcpServers) | length) == 0' "$tmp" >/dev/null; then
    rm -f "$MCPJSON" "$tmp"
    echo "mcp-xcode-combined: removed $NAME; $MCPJSON held nothing else, so it is gone too"
  else
    mv "$tmp" "$MCPJSON"
    echo "mcp-xcode-combined: removed $NAME from $MCPJSON"
  fi
fi

CODEXTOML="$TARGET/.codex/config.toml"
if [ -f "$CODEXTOML" ]; then
  python3 - "$CODEXTOML" "$NAME" <<'PY'
import sys
path, name = sys.argv[1], sys.argv[2]
header = f"[mcp_servers.{name}]"
lines = open(path).read().split("\n")
out, skipping, removed = [], False, False
for line in lines:
    s = line.strip()
    if s == header:
        skipping, removed = True, True
        continue
    if skipping and s.startswith("["):
        skipping = False
    if not skipping:
        out.append(line)
if removed:
    text = "\n".join(out).rstrip("\n") + "\n"
    open(path, "w").write(text if text.strip() else "")
    print(f"mcp-xcode-combined: removed {header} from {path}")
PY
fi
exit 0
