#!/bin/bash
# update.sh — regenerate AGENTS.md here: a list of @-references to every file in components/.
#
#   ./update.sh               write AGENTS.md in this directory and touch nothing else
#   ./update.sh --to-home     also copy it over ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md
#
# The second form replaces those two files, which are global to the machine. astra installs
# per repo and never globally, so it is off by default. When you ask for it, each file that
# exists is first copied to <file>.before-update.
set -euo pipefail
cd "$(dirname "$0")"
to_home=0
case "${1:-}" in
  "") ;;
  --to-home) to_home=1 ;;
  *) echo "usage: update.sh [--to-home]" >&2; exit 64 ;;
esac

outfile=AGENTS.md
here=$(pwd)

prefix="
# Important references
Immediately read all files referenced here:

"

echo "${prefix}" > "$outfile"
for file in components/*; do
    echo "@${here}/${file}" >> "$outfile"
done
echo "Updated $outfile"

if [ "$to_home" = 1 ]; then
    for target in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
        mkdir -p "$(dirname "$target")"
        [ ! -f "$target" ] || cp "$target" "$target.before-update"
        cp "$outfile" "$target" && echo "Updated $target"
    done
fi
exit 0
