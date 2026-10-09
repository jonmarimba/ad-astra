#!/usr/bin/env bash
# Check which app the XcodeBuildMCP-only open shim receives, without opening a UI.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
shim="$here/../xcode-mcp-front/xcodebuildmcp-bin/open"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

developer_dir="$scratch/Xcode.app/Contents/Developer"
mkdir -p "$developer_dir" "$scratch/Xcode.app/Contents/Applications/DeviceHub.app"
cat > "$scratch/fake-open" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$XCODEBUILDMCP_OPEN_RECORD"
EOF
chmod +x "$scratch/fake-open"

export DEVELOPER_DIR="$developer_dir"
export XCODEBUILDMCP_OPEN_BIN="$scratch/fake-open"
export XCODEBUILDMCP_OPEN_RECORD="$scratch/args"
"$shim" 'devices:///manage/select?id=one'
printf '%s\n' -a "$scratch/Xcode.app/Contents/Applications/DeviceHub.app" \
  'devices:///manage/select?id=one' > "$scratch/expected"
cmp "$scratch/expected" "$scratch/args"

"$shim" -a TextEdit "$scratch/example.txt"
printf '%s\n' -a TextEdit "$scratch/example.txt" > "$scratch/expected"
cmp "$scratch/expected" "$scratch/args"

rm -r "$scratch/Xcode.app/Contents/Applications/DeviceHub.app"
if "$shim" 'devices:///manage/select?id=one' > "$scratch/stdout" 2> "$scratch/stderr"; then
  echo 'missing Device Hub unexpectedly succeeded' >&2
  exit 1
fi
if ! rg -q 'no Device Hub' "$scratch/stderr"; then
  cat "$scratch/stderr" >&2
  exit 1
fi
echo 'xcodebuildmcp open routing: 3 checks passed'
