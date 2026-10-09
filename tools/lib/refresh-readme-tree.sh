#!/usr/bin/env bash
# refresh-readme-tree.sh — rewrite the template tree in README.md from `template.py tree`.
# test-template-tree.sh fails when the README block and the real tree differ; run this to fix it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
README="${1:-$ROOT/README.md}"
grep -q '<!-- template-tree:start -->' "$README" || { echo "refresh-readme-tree: no template-tree markers in $README" >&2; exit 65; }
tree="$(python3 "$ROOT/tools/lib/template.py" tree)"
python3 - "$README" "$tree" <<'PY'
import sys
path, tree = sys.argv[1], sys.argv[2]
s = open(path).read()
a = s.index("<!-- template-tree:start -->") + len("<!-- template-tree:start -->")
b = s.index("<!-- template-tree:end -->")
open(path, "w").write(s[:a] + "\n```\n" + tree + "\n```\n" + s[b:])
PY
echo "refresh-readme-tree: updated $README"
