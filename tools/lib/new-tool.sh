#!/usr/bin/env bash
# new-tool.sh — scaffold a new astra tool of one kind, with its uninstaller and its test, so the
# suite accepts it from the first commit. Run it through the front door:
#
#   astra new <name> --kind skill|repo|repo-config|machine|run-in-place
#
# The kinds are the four that tools/tests/test-tool-kinds.sh enforces, with `skill` as the common
# case of a repo tool whose only payload is a SKILL.md. CONTRIBUTING.md says what each one promises.
# The generated files are small and meant to be edited: they work as written, and the comments say
# what to change.
set -euo pipefail
ROOT="${ASTRA_NEW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
KINDS="skill, repo, repo-config, machine, run-in-place"
name="${1:-}"; kind="${2:-}"

[ -n "$name" ] || { echo "usage: astra new <name> --kind <$KINDS>" >&2; exit 64; }
case "$name" in
  [a-z0-9]*) ;;
  *) echo "astra new: a tool name uses lowercase letters, digits and hyphens, and starts with a letter or digit: $name" >&2; exit 64 ;;
esac
case "$name" in
  *[!a-z0-9-]*) echo "astra new: a tool name uses lowercase letters, digits and hyphens: $name" >&2; exit 64 ;;
esac
[ -n "$kind" ] || { echo "astra new: --kind is required: $KINDS" >&2; exit 64; }
case "$kind" in skill|repo|repo-config|machine|run-in-place) ;; *) echo "astra new: unknown kind '$kind'; the kinds are $KINDS" >&2; exit 64 ;; esac
[ ! -e "$ROOT/tools/$name" ] || { echo "astra new: tools/$name already exists" >&2; exit 73; }
upper="$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')"
D="$ROOT/tools/$name"
mkdir -p "$D"

# put <path> [mode]: write stdin to the path, filling in the tool's name.
put() { sed -e "s/__NAME__/$name/g" -e "s/__UPPER__/$upper/g" > "$1"; chmod "${2:-644}" "$1"; }

PLACE_LIB='. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"'

case "$kind" in
skill)
  mkdir -p "$ROOT/agents-and-prompts/skills/$name"
  put "$ROOT/agents-and-prompts/skills/$name/SKILL.md" <<'EOF'
---
name: __NAME__
description: Say in one sentence what this skill does and when an agent should use it.
---
# __NAME__

Write the skill here: when it applies, what to do, and what to check before reporting done.
EOF
  put "$D/install.sh" 755 <<'EOF'
#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the __NAME__ skill, placed into <repo>/.claude/skills/ and recorded in .astra/manifest.json.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_place_at __NAME__ \
  "agents-and-prompts/skills/__NAME__/SKILL.md:.claude/skills/__NAME__/SKILL.md"
EOF
  put "$D/uninstall.sh" 755 <<'EOF'
#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — the __NAME__ skill, removed from <repo> along with its manifest entry.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_remove __NAME__
EOF
  ;;
repo)
  put "$D/$name" 755 <<'EOF'
#!/usr/bin/env bash
# __NAME__ — say in one sentence what this tool does.
set -euo pipefail
echo "__NAME__: replace this line with the tool"
EOF
  put "$D/install.sh" 755 <<'EOF'
#!/usr/bin/env bash
# astra-scope: repo
# install.sh — __NAME__, placed into <repo>/.astra/__NAME__/ and recorded in .astra/manifest.json.
# Add a line to the pair list for every file the tool needs in the repo.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_place_at __NAME__ \
  "tools/__NAME__/__NAME__:.astra/__NAME__/__NAME__"
EOF
  put "$D/uninstall.sh" 755 <<'EOF'
#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — __NAME__, removed from <repo> along with its manifest entry.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_remove __NAME__
EOF
  ;;
repo-config)
  put "$D/install.sh" 755 <<'EOF'
#!/usr/bin/env bash
# astra-scope: repo-config
# install.sh — point a repo at the __NAME__ MCP server by writing its entry into <repo>/.mcp.json.
# This writes Claude's file only. A server that Qwen and Codex must also reach needs entries in
# .qwen/settings.json (httpUrl) and .codex/config.toml too: tools/mcp-xcode-combined is the model.
# Dependencies: jq.
set -uo pipefail
URL="${__UPPER___URL:-http://127.0.0.1:8000/mcp}"
NAME="__NAME__"
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="${2:-}"; shift 2 ;;
    *) echo "$NAME: unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: install.sh --into <repo>" >&2; exit 64; }
[ -d "$TARGET" ] || { echo "$NAME: no such directory: $TARGET" >&2; exit 66; }
command -v jq >/dev/null || { echo "$NAME: jq is missing; brew install jq" >&2; exit 69; }
MCPJSON="$TARGET/.mcp.json"
if [ -f "$MCPJSON" ]; then
  tmp="$(mktemp)"
  jq --arg name "$NAME" --arg url "$URL" '.mcpServers[$name] = {"type":"http","url":$url}' "$MCPJSON" > "$tmp" \
    || { rm -f "$tmp"; echo "$NAME: $MCPJSON is not valid JSON; fix it by hand." >&2; exit 65; }
  mv "$tmp" "$MCPJSON"
else
  jq -n --arg name "$NAME" --arg url "$URL" '{"mcpServers": {($name): {"type":"http","url":$url}}}' > "$MCPJSON"
fi
echo "$NAME: wrote $NAME -> $URL into $MCPJSON"
EOF
  put "$D/uninstall.sh" 755 <<'EOF'
#!/usr/bin/env bash
# astra-scope: repo-config
# uninstall.sh — remove the __NAME__ entry from <repo>/.mcp.json, and the file if that leaves it empty.
set -uo pipefail
NAME="__NAME__"
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --into) TARGET="${2:-}"; shift 2 ;;
    --deps) shift ;;
    *) echo "$NAME: unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: uninstall.sh --into <repo>" >&2; exit 64; }
MCPJSON="$TARGET/.mcp.json"
[ -f "$MCPJSON" ] || { echo "$NAME: no $MCPJSON; nothing to remove"; exit 0; }
tmp="$(mktemp)"
jq --arg name "$NAME" 'del(.mcpServers[$name])' "$MCPJSON" > "$tmp" || { rm -f "$tmp"; echo "$NAME: $MCPJSON is not valid JSON" >&2; exit 65; }
if [ "$(jq -c . "$tmp")" = '{"mcpServers":{}}' ]; then rm -f "$MCPJSON" "$tmp"; else mv "$tmp" "$MCPJSON"; fi
echo "$NAME: removed from $MCPJSON"
EOF
  ;;
machine)
  put "$D/Brewfile" 644 <<'EOF'
# One line per Homebrew formula this tool needs on the machine, for example:
# brew "jq"
EOF
  put "$D/deps.sh" 755 <<'EOF'
#!/usr/bin/env bash
# deps.sh — install or upgrade the software __NAME__ needs. `astra upgrade` runs this and nothing else,
# so keep it to software: no launchd reloads, no schedules, no app rebuilds.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
brewfile_upgrade "$HERE/Brewfile"
EOF
  put "$D/install.sh" 755 <<'EOF'
#!/usr/bin/env bash
# astra-scope: machine
# install.sh — set up __NAME__ on this machine, once. A repo install never runs this; it only
# prints "MACHINE __NAME__" with the command. Put the machine work after the deps step.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$HERE/deps.sh"
echo "__NAME__: ready"
EOF
  put "$D/uninstall.sh" 755 <<'EOF'
#!/usr/bin/env bash
# astra-scope: machine
# uninstall.sh — remove what __NAME__ set up on this machine. Shared software stays unless you pass --deps.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "__NAME__: nothing local to remove yet."
# For every formula in the Brewfile, remove it behind --deps:
#   uc_brew <formula> "why other tools may share it"
EOF
  ;;
run-in-place)
  printf 'Runs from the astra checkout as tools/%s/%s; it has nothing to install.\n' "$name" "$name" > "$D/RUN-IN-PLACE"
  put "$D/$name" 755 <<'EOF'
#!/usr/bin/env bash
# __NAME__ — say in one sentence what this tool does.
set -euo pipefail
echo "__NAME__: replace this line with the tool"
EOF
  ;;
esac

# The test. Every kind gets one: lib.sh assertions, a RED control, and `finish`.
mkdir -p "$ROOT/tools/tests"
T="$ROOT/tools/tests/test-$name.sh"
case "$kind" in
skill|repo|repo-config)
  case "$kind" in
    skill) landed='.claude/skills/__NAME__/SKILL.md' ;;
    repo) landed='.astra/__NAME__/__NAME__' ;;
    repo-config) landed='.mcp.json' ;;
  esac
  put "$T" 755 <<EOF
#!/usr/bin/env bash
# test-__NAME__.sh — __NAME__ installs into a repo, lands where it should, and uninstalls cleanly.
# Replace or extend these checks with ones for what the tool does.
set -uo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
# shellcheck disable=SC1091
. "\$HERE/lib.sh"
need git "xcode-select --install"
export HOME="\$SB/home"; mkdir -p "\$HOME"
R="\$SB/repo"; mkdir -p "\$R"; git -C "\$R" init -q

bash "\$ASTRA_ROOT/tools/__NAME__/install.sh" --into "\$R" > "\$SB/install.out" 2>&1
assert_eq 0 "\$?" "install succeeds"
assert_file "\$R/$landed" "the payload landed in the repo"
bash "\$ASTRA_ROOT/tools/__NAME__/uninstall.sh" --into "\$R" > "\$SB/uninstall.out" 2>&1
assert_eq 0 "\$?" "uninstall succeeds"
if [ -e "\$R/$landed" ]; then fail "the payload is still in the repo after uninstall"; else pass "the payload is gone after uninstall"; fi
bash "\$ASTRA_ROOT/tools/__NAME__/install.sh" > "\$SB/red.out" 2>&1
assert_eq 64 "\$?" "RED: install without --into exits 64"
finish
EOF
  ;;
machine)
  put "$T" 755 <<'EOF'
#!/usr/bin/env bash
# test-__NAME__.sh — __NAME__ is declared as a machine tool, ships a deps.sh, and its uninstaller
# runs without touching shared software. Replace or extend these checks with ones for what it does.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
assert_contains "$ASTRA_ROOT/tools/__NAME__/install.sh" "astra-scope: machine" "install.sh declares the machine kind"
[ -x "$ASTRA_ROOT/tools/__NAME__/deps.sh" ] && pass "deps.sh is executable, so astra upgrade can run it" || fail "deps.sh is missing or not executable"
bash "$ASTRA_ROOT/tools/__NAME__/uninstall.sh" > "$SB/un.out" 2>&1
assert_eq 0 "$?" "a plain uninstall succeeds"
bash "$ASTRA_ROOT/tools/__NAME__/uninstall.sh" --nonsense > "$SB/red.out" 2>&1
assert_eq 64 "$?" "RED: an unknown flag exits 64"
finish
EOF
  ;;
run-in-place)
  put "$T" 755 <<'EOF'
#!/usr/bin/env bash
# test-__NAME__.sh — __NAME__ runs from the checkout. Replace or extend these checks with ones for what it does.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
out="$(bash "$ASTRA_ROOT/tools/__NAME__/__NAME__" 2>&1)"
assert_eq 0 "$?" "the tool runs"
assert_eq "__NAME__: replace this line with the tool" "$out" "and prints its placeholder line"
[ ! -e "$ASTRA_ROOT/tools/__NAME__/install.sh" ] && pass "a run-in-place tool has no installer" || fail "install.sh found next to RUN-IN-PLACE"
bash "$ASTRA_ROOT/tools/__NAME__/no-such-file" > "$SB/red.out" 2>&1
[ $? -ne 0 ] && pass "RED: running a file that does not exist fails" || fail "RED control passed against a missing file"
finish
EOF
  ;;
esac
chmod +x "$T"

echo "created tools/$name ($kind) and tools/tests/test-$name.sh"
[ "$kind" != skill ] || echo "  edit agents-and-prompts/skills/$name/SKILL.md"
echo "  add it to a set in tools/lib/templates.json if repos should get it from a template"
echo "  run: bash tools/tests/test-$name.sh && bash tools/tests/test-tool-kinds.sh"
