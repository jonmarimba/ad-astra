#!/usr/bin/env zsh
set -euo pipefail

# setup-mcp.sh
#
# Configure the same MCP server set for:
#   - Claude Code: ./.mcp.json via `claude mcp add --scope project`
#   - Qwen Code:   ./.qwen/settings.json
#   - Codex CLI:   ./.codex/config.toml
#
# Default action with no args: install all.
#
# Usage:
#   ./scripts/setup-mcp.sh
#   ./scripts/setup-mcp.sh --install
#   ./scripts/setup-mcp.sh --install xcode ios-simulator
#   ./scripts/setup-mcp.sh --disable
#   ./scripts/setup-mcp.sh --disable xcode
#   ./scripts/setup-mcp.sh --list
#   ./scripts/setup-mcp.sh --help

typeset -a ALL_MCPS=(
  mac-control-mcp
  xcode-mcp-server
  xcode
  ios-simulator
  XcodeBuildMCP
  mobile-mcp
  kickerd
)

readonly MAC_CONTROL_MCP_EXECUTABLE="/Applications/MacControlMCP.app/Contents/MacOS/MacControlMCP"
readonly MAC_CONTROL_MCP_RELEASES="https://github.com/AdelElo13/mac-control-mcp/releases"

log() {
  printf "\n==> %s\n" "$*"
}

warn() {
  printf "\n!! %s\n" "$*" >&2
}

die() {
  warn "$*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

contains_mcp() {
  local wanted="$1"
  local mcp

  for mcp in "${ALL_MCPS[@]}"; do
    [[ "$mcp" == "$wanted" ]] && return 0
  done

  return 1
}

usage() {
  cat <<'EOF'
Usage:
  setup-mcp.sh
  setup-mcp.sh --install [mcp-name ...]
  setup-mcp.sh --disable [mcp-name ...]
  setup-mcp.sh --list
  setup-mcp.sh --help

Default:
  With no arguments, installs all MCPs.

Options:
  --install [mcp-name ...]
    Install one or more MCPs.
    With no MCP names, installs all.

  --disable [mcp-name ...]
    disable one or more MCPs.
    With no MCP names, disables all.

  --list
    Show MCPs this script knows how to install.

  --help, -h
    Show this help.

Known MCPs:
  mac-control-mcp
  xcode-mcp-server
  xcode
  ios-simulator
  XcodeBuildMCP
  mobile-mcp
  kickerd

Files:
  .mcp.json for Claude Code CLI
  .qwen/settings.json for qwen CLI
  .codex/config.toml for Codex CLI

EOF
}

list_mcps() {
  printf "Available MCPs:\n"

  local mcp
  for mcp in "${ALL_MCPS[@]}"; do
    printf "  %s\n" "$mcp"
  done
}

resolve_targets() {
  # Prints selected MCP names, one per line.
  # Empty selection means all.
  if [[ "$#" -eq 0 ]]; then
    printf "%s\n" "${ALL_MCPS[@]}"
    return
  fi

  local target
  for target in "$@"; do
    if ! contains_mcp "$target"; then
      warn "Unknown MCP: $target"
      list_mcps >&2
      exit 2
    fi

    printf "%s\n" "$target"
  done
}

ensure_homebrew() {
  if need_cmd brew; then
    return
  fi

  die "Homebrew is not installed. Install it first: https://brew.sh"
}

ensure_node_npx() {
  if need_cmd node && need_cmd npm && need_cmd npx; then
    return
  fi

  ensure_homebrew
  log "Installing Node.js..."
  brew install node
}

ensure_uvx() {
  if need_cmd uvx; then
    return
  fi

  ensure_homebrew
  log "Installing uv..."
  brew install uv
}

ensure_claude() {
  if need_cmd claude; then
    return
  fi

  ensure_node_npx
  log "Installing Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code
}

ensure_xcode_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    return
  fi

  log "Launching Xcode Command Line Tools installer..."
  xcode-select --install || true
  die "Run this script again after Xcode Command Line Tools finish installing."
}

ensure_xcrun() {
  ensure_xcode_tools

  if need_cmd xcrun; then
    return
  fi

  die "xcrun not found even though Xcode tools appear installed."
}

ensure_jq() {
  if need_cmd jq; then
    return
  fi

  ensure_homebrew
  log "Installing jq..."
  brew install jq
}

ensure_python3() {
  if need_cmd python3; then
    return
  fi

  ensure_homebrew
  log "Installing python3..."
  brew install python
}

ensure_mac_control_mcp() {
  if [[ -x "$MAC_CONTROL_MCP_EXECUTABLE" ]]; then
    return
  fi

  die "MacControlMCP is not installed at $MAC_CONTROL_MCP_EXECUTABLE. Install it from $MAC_CONTROL_MCP_RELEASES"
}

ensure_npm_package_available() {
  local package="$1"

  ensure_node_npx

  log "Checking npm package: $package"
  npm view "$package" version >/dev/null
}

ensure_uvx_package_available() {
  ensure_uvx

  # Renamed upstream (several unrelated projects shared the old name, and Xcode now
  # ships its own built-in MCP server) — the old PyPI name still forwards for compat,
  # so check the current name first and fall back to it rather than fail outright.
  log "Checking uvx package: drews-xcode-mcp"

  if uvx --from drews-xcode-mcp drews-xcode-mcp --help >/dev/null 2>&1; then
    return
  fi

  if uvx drews-xcode-mcp --help >/dev/null 2>&1; then
    return
  fi

  log "Checking uvx package: xcode-mcp-server (old name, still forwards)"

  if uvx --from xcode-mcp-server xcode-mcp-server --help >/dev/null 2>&1; then
    return
  fi

  if uvx xcode-mcp-server --help >/dev/null 2>&1; then
    return
  fi

  warn "Could not verify drews-xcode-mcp (or the old xcode-mcp-server name) through uvx."
  warn "Continuing anyway; uvx may resolve it lazily when the MCP starts."
}

ensure_deps_for_target() {
  local name="$1"

  case "$name" in
    mac-control-mcp)
      ensure_mac_control_mcp
      ensure_claude
      ;;
    xcode-mcp-server)
      ensure_uvx
      ensure_claude
      ensure_uvx_package_available
      ;;
    xcode)
      ensure_xcrun
      ensure_claude
      ;;
    ios-simulator)
      ensure_node_npx
      ensure_claude
      ensure_npm_package_available "ios-simulator-mcp"
      ;;
    XcodeBuildMCP)
      ensure_node_npx
      ensure_claude
      ensure_npm_package_available "xcodebuildmcp"
      ;;
    mobile-mcp)
      ensure_node_npx
      ensure_claude
      ensure_npm_package_available "@mobilenext/mobile-mcp"
      ;;
    kickerd)
      # No extra deps — kickerd daemon provides HTTP endpoint at http://127.0.0.1:37373/mcp
      ;;
    *)
      die "Unknown MCP target: $name"
      ;;
  esac
}

claude_disable_one() {
  local name="$1"

  if ! need_cmd claude; then
    warn "claude CLI not found; skipping Claude disable for $name."
    return
  fi

  claude mcp remove "$name" --scope project >/dev/null 2>&1 || true
}

install_claude_one() {
  local name="$1"

  log "Installing Claude Code MCP: $name"

  claude_disable_one "$name"

  case "$name" in
    mac-control-mcp)
      claude mcp add --scope project mac-control-mcp -- "$MAC_CONTROL_MCP_EXECUTABLE"
      ;;
    xcode-mcp-server)
      claude mcp add --scope project --transport stdio xcode-mcp-server "$(command -v uvx)" drews-xcode-mcp
      ;;
    xcode)
      claude mcp add --scope project --transport stdio xcode -- xcrun mcpbridge
      ;;
    ios-simulator)
      claude mcp add --scope project ios-simulator npx ios-simulator-mcp
      ;;
    XcodeBuildMCP)
      claude mcp add --scope project XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp
      ;;
    mobile-mcp)
      claude mcp add --scope project mobile-mcp -- npx -y @mobilenext/mobile-mcp@latest
      ;;
    kickerd)
      claude mcp add --scope project --transport http kickerd http://127.0.0.1:37373/mcp
      ;;
    *)
      die "Unknown MCP target: $name"
      ;;
  esac
}

disable_claude_one() {
  local name="$1"

  log "Disabling Claude Code MCP: $name"
  claude_disable_one "$name"
}

maybe_disable_empty_mcp_json() {
  if [[ ! -f .mcp.json ]]; then
    return
  fi

  if ! need_cmd jq; then
    warn "jq not found; leaving .mcp.json in place."
    return
  fi

  local count
  count="$(jq '.mcpServers // {} | length' .mcp.json 2>/dev/null || echo 1)"

  if [[ "$count" == "0" ]]; then
    log "Disabling empty .mcp.json"
    rm .mcp.json
  else
    log "Leaving .mcp.json because it still contains $count MCP server(s)"
  fi
}

qwen_json_for_target() {
  local name="$1"

  case "$name" in
    mac-control-mcp)
      cat <<EOF
{
  "command": "$MAC_CONTROL_MCP_EXECUTABLE",
  "args": []
}
EOF
      ;;
    xcode-mcp-server)
      cat <<EOF
{
  "command": "$(command -v uvx)",
  "args": ["drews-xcode-mcp"]
}
EOF
      ;;
    xcode)
      cat <<'EOF'
{
  "command": "xcrun",
  "args": ["mcpbridge"]
}
EOF
      ;;
    ios-simulator)
      cat <<'EOF'
{
  "command": "npx",
  "args": ["ios-simulator-mcp"]
}
EOF
      ;;
    XcodeBuildMCP)
      cat <<'EOF'
{
  "command": "npx",
  "args": ["-y", "xcodebuildmcp@latest", "mcp"]
}
EOF
      ;;
    mobile-mcp)
      cat <<'EOF'
{
  "command": "npx",
  "args": ["-y", "@mobilenext/mobile-mcp@latest"]
}
EOF
      ;;
    kickerd)
      cat <<'EOF'
{
  "type": "http",
  "url": "http://127.0.0.1:37373/mcp"
}
EOF
      ;;
    *)
      die "Unknown MCP target: $name"
      ;;
  esac
}

ensure_qwen_file() {
  mkdir -p .qwen
  ensure_jq

  if [[ ! -f .qwen/settings.json ]]; then
    cat > .qwen/settings.json <<'EOF'
{
  "mcpServers": {}
}
EOF
  fi

  jq '.mcpServers = (.mcpServers // {})' .qwen/settings.json > .qwen/settings.json.tmp
  mv .qwen/settings.json.tmp .qwen/settings.json
}

install_qwen_one() {
  local name="$1"

  log "Installing Qwen Code MCP: $name"

  ensure_qwen_file

  local server_json
  server_json="$(qwen_json_for_target "$name")"

  jq \
    --arg name "$name" \
    --argjson server "$server_json" \
    '.mcpServers[$name] = $server' \
    .qwen/settings.json > .qwen/settings.json.tmp

  mv .qwen/settings.json.tmp .qwen/settings.json
}

disable_qwen_one() {
  local name="$1"

  log "Disabling Qwen Code MCP: $name"

  [[ -f .qwen/settings.json ]] || return

  if ! need_cmd jq; then
    warn "jq not found; cannot edit .qwen/settings.json safely."
    return
  fi

  jq --arg name "$name" 'del(.mcpServers[$name])' \
    .qwen/settings.json > .qwen/settings.json.tmp

  mv .qwen/settings.json.tmp .qwen/settings.json
}

maybe_disable_empty_qwen_dir() {
  [[ -f .qwen/settings.json ]] || {
    rmdir .qwen 2>/dev/null || true
    return
  }

  if ! need_cmd jq; then
    return
  fi

  local count
  count="$(jq '.mcpServers // {} | length' .qwen/settings.json 2>/dev/null || echo 1)"

  if [[ "$count" == "0" ]]; then
    log "Disabling empty .qwen/settings.json"
    rm .qwen/settings.json
    rmdir .qwen 2>/dev/null || true
  fi
}

codex_block_for_target() {
  local name="$1"

  case "$name" in
    mac-control-mcp)
      cat <<EOF
[mcp_servers.mac-control-mcp]
command = "$MAC_CONTROL_MCP_EXECUTABLE"
args = []
EOF
      ;;
    xcode-mcp-server)
      cat <<EOF
[mcp_servers.xcode-mcp-server]
command = "$(command -v uvx)"
args = ["drews-xcode-mcp"]
EOF
      ;;
    xcode)
      cat <<'EOF'
[mcp_servers.xcode]
command = "xcrun"
args = ["mcpbridge"]
EOF
      ;;
    ios-simulator)
      cat <<'EOF'
[mcp_servers.ios-simulator]
command = "npx"
args = ["ios-simulator-mcp"]
EOF
      ;;
    XcodeBuildMCP)
      cat <<'EOF'
[mcp_servers.XcodeBuildMCP]
command = "npx"
args = ["-y", "xcodebuildmcp@latest", "mcp"]
EOF
      ;;
    mobile-mcp)
      cat <<'EOF'
[mcp_servers.mobile-mcp]
command = "npx"
args = ["-y", "@mobilenext/mobile-mcp@latest"]
EOF
      ;;
    kickerd)
      cat <<'EOF'
[mcp_servers.kickerd]
url = "http://127.0.0.1:37373/mcp"
transport = "http"
EOF
      ;;
    *)
      die "Unknown MCP target: $name"
      ;;
  esac
}

ensure_codex_file() {
  mkdir -p .codex
  touch .codex/config.toml
  ensure_python3
}

disable_codex_block_one() {
  local name="$1"

  [[ -f .codex/config.toml ]] || return

  ensure_python3

  python3 - "$name" .codex/config.toml <<'PY'
import re
import sys
from pathlib import Path

name = sys.argv[1]
path = Path(sys.argv[2])
text = path.read_text()

pattern = re.compile(
    rf'(?ms)^\[mcp_servers\.{re.escape(name)}\]\n'
    rf'.*?'
    rf'(?=^\[mcp_servers\.|\Z)'
)

text = pattern.sub('', text)
text = re.sub(r'\n{3,}', '\n\n', text).strip()

if text:
    path.write_text(text + '\n')
else:
    path.write_text('')
PY
}

install_codex_one() {
  local name="$1"

  log "Installing Codex MCP: $name"

  ensure_codex_file
  disable_codex_block_one "$name"

  {
    if [[ -s .codex/config.toml ]]; then
      printf "\n"
    fi
    codex_block_for_target "$name"
    printf "\n"
  } >> .codex/config.toml
}

disable_codex_one() {
  local name="$1"

  log "Disabling Codex MCP: $name"
  disable_codex_block_one "$name"
}

maybe_disable_empty_codex_dir() {
  if [[ -f .codex/config.toml && ! -s .codex/config.toml ]]; then
    log "Disabling empty .codex/config.toml"
    rm .codex/config.toml
  fi

  rmdir .codex 2>/dev/null || true
}

install_targets() {
  local -a targets=("$@")
  local name

  for name in "${targets[@]}"; do
    ensure_deps_for_target "$name"
    install_claude_one "$name"
    install_qwen_one "$name"
    install_codex_one "$name"
  done

  log "Installed selected MCP config for Claude Code, Qwen Code, and Codex"
}

disable_targets() {
  local -a targets=("$@")
  local name

  for name in "${targets[@]}"; do
    disable_claude_one "$name"
    disable_qwen_one "$name"
    disable_codex_one "$name"
  done

  maybe_disable_empty_mcp_json
  maybe_disable_empty_qwen_dir
  maybe_disable_empty_codex_dir

  log "Disabled selected MCP config for Claude Code, Qwen Code, and Codex"
}

main() {
  local action="install"
  local -a names

  case "${1:-}" in
    "")
      action="install"
      ;;
    --install)
      action="install"
      shift
      ;;
    --disable)
      action="disable"
      shift
      ;;
    --list)
      list_mcps
      exit 0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      warn "Unknown option: $1"
      usage >&2
      exit 2
      ;;
    *)
      warn "Unexpected argument without --install/--disable: $1"
      usage >&2
      exit 2
      ;;
  esac

  names=("${(@f)$(resolve_targets "$@")}")

  case "$action" in
    install)
      install_targets "${names[@]}"
      ;;
    disable)
      disable_targets "${names[@]}"
      ;;
    *)
      die "Internal error: unknown action $action"
      ;;
  esac
}

main "$@"
