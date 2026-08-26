#!/usr/bin/env bash
# test-omniroute-speed.sh — throughput must be reported as a median over real generations.
#
# THE FAILURE THIS GUARDS. Averaging tokens_out/duration across every row in call_logs put
# glm-5.2 at 716-792 tok/s on 2026-08-26 when sustained throughput was about 114. Four calls
# that returned in under half a second carried the mean. Anyone choosing a model on that
# number would have picked the wrong one by a factor of seven.
#
# The fixture below reproduces that shape exactly: a hundred honest generations near 114 tok/s
# plus four sub-second blips near 750. Assertion 1 fails if the tool reports the average.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
. ./lib.sh
TOOL="$HOME/svnCheckouts/js-db-ad-astra/tools/omniroute-speed/omniroute-speed"
[ -f "$TOOL" ] || { fail "omniroute-speed missing at $TOOL"; finish; exit 1; }
need python3 "install python3"
need sqlite3 "brew install sqlite"

DB="$SB/storage.sqlite"
sqlite3 "$DB" <<'SQL'
CREATE TABLE call_logs (
  id TEXT PRIMARY KEY, timestamp TEXT NOT NULL, status INTEGER, model TEXT,
  duration INTEGER DEFAULT 0, tokens_out INTEGER DEFAULT 0,
  tokens_cache_read INTEGER DEFAULT NULL
);
SQL

python3 - "$DB" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
rows = []
n = 0
# 100 honest generations: 1000 tokens in 8772ms -> ~114 tok/s
for i in range(100):
    rows.append(("real%d" % i, "2026-08-20T10:00:00Z", 200, "glm-5.2", 8772, 1000, None))
# 4 blips: 60 tokens in 80ms -> 750 tok/s. These are what wrecked the average.
for i in range(4):
    rows.append(("blip%d" % i, "2026-08-20T10:00:00Z", 200, "glm-5.2", 80, 60, None))
# a cache hit that never generated anything: 5000 tokens in 12ms
rows.append(("cached", "2026-08-20T10:00:00Z", 200, "glm-5.2", 12, 5000, 4800))
# a failed call
rows.append(("failed", "2026-08-20T10:00:00Z", 500, "glm-5.2", 90000, 900, None))
# a second model, slower, few samples, and one older row for the --since test
rows.append(("slow1", "2026-08-20T10:00:00Z", 200, "qwen3.6-27b", 50000, 1000, None))
rows.append(("slow2", "2026-08-20T10:00:00Z", 200, "qwen3.6-27b", 50000, 1000, None))
rows.append(("ancient", "2026-07-01T10:00:00Z", 200, "ancient-model", 1000, 1000, None))
db.executemany("INSERT INTO call_logs VALUES (?,?,?,?,?,?,?)", rows)
db.commit()
PY

run() { OMNIROUTE_DB="$DB" python3 "$TOOL" "$@" 2>&1; }

# 1. THE LIVE FAILURE. The median must land near 114, not near the ~139 average the blips produce.
out="$(run --model glm)"
val="$(printf '%s\n' "$out" | awk '/glm-5.2/ {print int($2)}')"
if [ -n "$val" ] && [ "$val" -ge 110 ] && [ "$val" -le 118 ]; then
  pass "glm-5.2 reports sustained median ~114 tok/s (got $val)"
else
  fail "median wrong — expected 110-118, got '$val' from: $out"
fi

# 2. RED CONTROL. Assertion 1 proves nothing unless the naive statistic would have been WRONG
#    on this same data. Compute the average the old way, over the identical rows the tool
#    selects, and require it to be materially higher than the median the tool reported. If the
#    two agree, the fixture does not reproduce the failure and assertion 1 is a tautology.
avg="$(sqlite3 "$DB" "SELECT CAST(AVG(CAST(tokens_out AS REAL)/(duration/1000.0)) AS INT)
  FROM call_logs WHERE model='glm-5.2' AND tokens_out > 50 AND duration > 0
  AND (tokens_cache_read IS NULL OR tokens_cache_read = 0) AND status < 400;")"
med="$(run --model glm --min-tokens 50 | awk '/glm-5.2/ {print int($2)}')"
if [ -n "$avg" ] && [ -n "$med" ] && [ "$avg" -gt $((med + 15)) ]; then
  pass "RED control: naive average is $avg on this data, median is $med — the blips are real"
else
  fail "RED control inconclusive — average $avg vs median $med; fixture does not reproduce the bug"
fi

# 3. A CACHE HIT MUST NOT COUNT. 5000 tokens in 12ms is 416,000 tok/s and would dominate
#    any statistic that let it in.
out="$(run --model glm --min-tokens 50)"
case "$out" in
  *4166*|*41666*|*416666*) fail "cache hit counted as a generation: $out";;
  *) pass "cache hits excluded";;
esac

# 4. A FAILED CALL MUST NOT COUNT.
out="$(run --model glm)"
val="$(printf '%s\n' "$out" | awk '/glm-5.2/ {print int($2)}')"
[ "$val" -ge 110 ] && pass "failed call excluded (median unmoved)" || fail "failed call dragged the median to $val"

# 5. THIN SAMPLES ARE MARKED. Two calls is not a throughput measurement.
out="$(run --model qwen)"
case "$out" in
  *"(thin)"*) pass "a two-call median is marked thin";;
  *) fail "thin sample not marked: $out";;
esac

# 6. --since FILTERS, and its absence is visible.
out="$(run --since 2026-08-01)"
case "$out" in
  *ancient-model*) fail "--since did not exclude the July row: $out";;
  *) pass "--since excludes older calls";;
esac

# 7. NO SILENT EMPTY. An over-tight filter must say so rather than printing nothing.
out="$(run --model nosuchmodel)"
case "$out" in
  *"no calls above"*) pass "empty result names the filter that emptied it";;
  *) fail "empty result was silent — got: '$out'";;
esac

# 8. RED CONTROL. A missing database must fail loudly, not report zero models.
OMNIROUTE_DB="$SB/does-not-exist.sqlite" python3 "$TOOL" >/dev/null 2>&1
[ $? -eq 2 ] && pass "RED control: missing database exits nonzero" || fail "missing database did not fail"

finish
