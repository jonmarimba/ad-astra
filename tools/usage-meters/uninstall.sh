#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — usage-meters, removed from <repo> along with its manifest entry and the
# config entries its installer wrote in .claude/settings.json, .qwen/settings.json and
# .codex/config.toml.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_remove usage-meters
