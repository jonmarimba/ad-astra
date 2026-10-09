#!/bin/bash
# List every tool exposed by a running Streamable HTTP MCP front.
# Usage: list-live-tools.sh [http://127.0.0.1:8767/mcp]
# Needs curl, jq, and a reachable MCP endpoint. Prints one tool name per line.
set -euo pipefail

endpoint="${1:-http://127.0.0.1:8767/mcp}"
init_response="$(curl -fsS --max-time 20 -D - -X POST "$endpoint" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-06-18' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"list-live-tools","version":"1"}}}')"
session="$(printf '%s\n' "$init_response" | awk 'tolower($1) == "mcp-session-id:" {gsub("\r", "", $2); print $2; exit}')"
if [ -z "$session" ]; then
  printf 'MCP initialize returned no session ID:\n%s\n' "$init_response" >&2
  exit 1
fi

cursor=''
while :; do
  if [ -n "$cursor" ]; then
    params="$(jq -nc --arg cursor "$cursor" '{cursor: $cursor}')"
  else
    params='{}'
  fi
  request="$(jq -nc --argjson params "$params" '{jsonrpc:"2.0",id:2,method:"tools/list",params:$params}')"
  response="$(curl -fsS --max-time 60 -X POST "$endpoint" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H 'MCP-Protocol-Version: 2025-06-18' \
    -H "Mcp-Session-Id: $session" \
    -d "$request")"
  payload="$(printf '%s\n' "$response" | jq -Rr 'select(startswith("data: ")) | .[6:]' | jq -s 'last')"
  if [ -z "$payload" ] || [ "$payload" = 'null' ] || ! printf '%s\n' "$payload" | jq -e '.result.tools | type == "array"' >/dev/null; then
    printf 'MCP tools/list returned no tool array:\n%s\n' "$response" >&2
    exit 1
  fi
  printf '%s\n' "$payload" | jq -r '.result.tools[].name'
  cursor="$(printf '%s\n' "$payload" | jq -r '.result.nextCursor // empty')"
  [ -n "$cursor" ] || break
done
