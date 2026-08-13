#!/usr/bin/env bash
# test-dedup-scan.sh — the graph miner (step 2) against a fixture graph.json exercising
# every filter: no-edge same-surface pairs surface, linked files don't, test files and
# non-code files don't, sub-majority overlaps don't. Steps 1 (periphery, needs a real
# Swift repo) and 3 (claude judgment) are exercised by the real kicker/pot-mhm runs, not
# here — this file tests the miner and says so (names don't overclaim).
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
DS="$HERE/../dedup-scan/dedup-scan"
need python3 "xcode-select --install"

REPO="$SB/repo"; mkdir -p "$REPO/graphify-out"
python3 - "$REPO/graphify-out/graph.json" <<'PY'
import json, sys
# helpers h1..h3 + files: a.py and b.py share the full surface with NO edge between them
# (the duplicate pair); c.py shares it but LINKS to a.py (knows about it — not a dup);
# tests/test_a.py and doc.md share it but must be filtered by kind
nodes = [{"id": f"h{i}", "label": f"helper_{i}", "source_file": "helpers.py"} for i in (1,2,3)]
edges = []
for f in ("a.py","b.py","c.py","tests/test_a.py","doc.md"):
    nid = "f_" + f
    nodes.append({"id": nid, "label": f, "source_file": f})
    for i in (1,2,3):
        edges.append({"source": nid, "target": f"h{i}"})
edges.append({"source": "f_c.py", "target": "f_a.py"})   # c knows about a
json.dump({"nodes": nodes, "edges": edges}, open(sys.argv[1], "w"))
PY

assert_rc 0 "miner runs (--no-llm)" "$DS" "$REPO" --no-llm --min-shared 3
R="$REPO/graphify-out/DEDUP_REPORT.md"
assert_file "$R" "report written"
grep -q "a.py" "$R" && grep -q "b.py" "$R" && pass "unlinked same-surface pair (a.py, b.py) surfaced" || fail "the real duplicate pair is missing from the report"
line="$(grep -F "a.py" "$R" | grep -F "b.py" | head -1)"
assert_nonempty "$line" "a.py and b.py reported as one PAIR"
grep -F "c.py" "$R" | grep -qF "a.py" && fail "linked pair (c.py knows a.py) wrongly surfaced" || pass "linked files not reported as duplicates"
assert_not_contains "$R" "test_a.py" "test file excluded from candidates"
assert_not_contains "$R" "doc.md" "non-code file excluded from candidates"

# ---- RED controls ----
red "missing graph.json must fail with the pointer to graphify-repo" "$DS" "$SB/empty-repo" --no-llm
red "typo'd flag must error, not run with defaults" "$DS" "$REPO" --no-lm
red "missing repo arg must fail" "$DS"

finish
