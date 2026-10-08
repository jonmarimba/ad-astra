#!/usr/bin/env bash
# test-no-gnu-only-commands.sh — shell tools must run on a stock Mac.
#
# macOS ships bash 3.2 and BSD userland. On 2026-10-05 a peer review's fix to
# repo-daemon-run.sh called `flock`, which is util-linux and absent here: every repo daemon
# launch failed to write its port file, and the test that caught it was misread as a hang
# for two days. This scans the shell scripts for commands and bash features a stock Mac
# lacks, so the next one fails at review time. A script that genuinely needs one of these
# must say so with a `# portability-ok: <reason>` comment on the same line.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ASTRA_ROOT" || exit 1

# command position: start of line, or after ; & | ( or $(  — so prose and comments never match
CMDPOS='(^|[;&|(]|\$\()[[:space:]]*'
GNU="flock|timeout|sha256sum|md5sum|setsid|ionice|inotifywait|shuf|tac|numfmt"
GNUARGS="stat -c|date -d|readlink -f|xargs -r|sed -r|grep -P|sed -i[[:space:]]+[^'\"]"   # BSD sed -i needs an argument
BASH4='mapfile|readarray|declare -A|local -A'

scan() {  # scan <file>: print findings, one per line
  grep -nE "${CMDPOS}(${GNU})[[:space:]]|${CMDPOS}(${GNUARGS})|${CMDPOS}(${BASH4})[[:space:]]" "$1" 2>/dev/null \
    | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v 'portability-ok:' \
    | sed "s#^#$1:#"
}

shell_scripts() {
  git ls-files -z | while IFS= read -r -d '' f; do
    case "$f" in vendor/*|tools/tool-templates/colloquium/*|notes/*) continue ;; esac
    [ -f "$f" ] || continue
    case "$f" in *.sh) echo "$f"; continue ;; esac
    head -c 64 "$f" 2>/dev/null | head -1 | grep -qE '^#!.*(bash|/sh)( |$)' && echo "$f"
  done
}

echo "== the scan can see a violation (RED control, run first)"
printf '#!/bin/bash\nflock -n 9 || exit 75\n' > "$SB/planted.sh"
planted="$(scan "$SB/planted.sh")"
assert_nonempty "$planted" "RED control: a planted flock is detected"
printf '#!/bin/bash\nmapfile -t a < /dev/null\n' > "$SB/planted2.sh"
assert_nonempty "$(scan "$SB/planted2.sh")" "RED control: a planted bash-4 mapfile is detected"
printf '#!/bin/bash\n# flock is not used here\necho "timeout is a word"\nflock -n 9 || true # portability-ok: linux-only helper\n' > "$SB/clean.sh"
assert_empty "$(scan "$SB/clean.sh")" "comments, prose and a portability-ok line are not findings"

echo "== no shell script in the tree uses a GNU-only command or a bash-4 feature"
files="$(shell_scripts)"
assert_nonempty "$files" "shell scripts were found (tautology guard)"
found=""
for f in $files; do found="$found$(scan "$f")"$'\n'; done
found="$(printf '%s' "$found" | sed '/^$/d')"
assert_empty "$found" "stock macOS runs every shell script's commands"
[ -z "$found" ] || printf '%s\n' "$found" | cut -c1-170 | sed 's/^/        /'
finish
