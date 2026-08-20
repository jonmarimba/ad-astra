#!/bin/bash

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

#
# update targets
#
updateTargets="$HOME/.claude/CLAUDE.md $HOME/.codex/AGENTS.md"
for target in $updateTargets; do
    cp "$outfile" "$target" && echo "Updated $target"
done
exit 0
