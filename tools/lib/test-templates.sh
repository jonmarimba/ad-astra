#!/usr/bin/env bash
# Templates must be NON-EXCLUSIVE. Two templates sharing a tool must coexist, and
# uninstalling one must not remove a tool the other still needs.
#
# This test caught the property failing on the day it was written: uninstalling
# kicker-dev removed mcp-xcode and mcp-mac-control-mcp while swift-ios was
# installed and using both. Keep it red-capable — it is the only thing standing
# between "templates" and "the second install silently breaks the first".
set -u
A="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v jq >/dev/null || { echo "MISSING DEPENDENCY: jq"; exit 1; }
T="$(mktemp -d)/repo"; git clone --quiet ~/svnCheckouts/js-llmKicker "$T" 2>/dev/null || { echo "clone failed"; exit 1; }
fail=()

python3 "$A/tools/lib/template.py" install swift-ios --into "$T" >/dev/null 2>&1
python3 "$A/tools/lib/template.py" install kicker-dev --into "$T" >/dev/null 2>&1
out="$(python3 "$A/tools/lib/template.py" uninstall kicker-dev --into "$T" 2>&1)"
rc=$?
after="$(jq -r '.mcpServers|keys|join(",")' "$T/.mcp.json" 2>/dev/null)"

for need in xcode mac-control-mcp XcodeBuildMCP ios-simulator mobile-mcp; do
  echo "$after" | grep -q "$need" || fail+=("swift-ios lost $need after uninstalling an overlapping template")
done
echo "$after" | grep -q kickerd && fail+=("kickerd survived its own template's uninstall")
echo "$out" | grep -q "KEPT" || fail+=("shared tools were not reported as KEPT")
[ $rc -eq 0 ] || fail+=("uninstall exited $rc on a successful run")

rm -rf "$(dirname "$T")"
if [ ${#fail[@]} -eq 0 ]; then echo "templates: non-exclusive overlap holds"; exit 0; fi
printf 'FAIL: %s\n' "${fail[@]}"; exit 1
