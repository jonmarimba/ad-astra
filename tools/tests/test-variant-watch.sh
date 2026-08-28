#!/usr/bin/env bash
# test-variant-watch.sh — the watcher must not lie, and must not cost more than it is worth.
#
# Two separate hazards. It reports models Jonathan could run, so announcing an unrunnable or
# non-existent one wastes his attention. And it queries Hugging Face per candidate, which on
# 2026-08-28 rate-limited this IP during the tool's own verification runs — and that limit
# blocks the daily model scan too, so an expensive watcher takes out the thing it runs inside.
#
# No network. Every assertion is against the shipped file.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/../ambrosio/variant-watch"
ok=0; failed=0
pass(){ printf '  ok:   %s\n' "$1"; ok=$((ok+1)); }
fail(){ printf '  FAIL: %s\n' "$1"; failed=$((failed+1)); }
[ -x "$TOOL" ] || { fail "variant-watch missing or not executable at $TOOL"; exit 1; }

OUT="$(mktemp)"
(python3 - "$TOOL" <<'PY'
import sys, io, os, contextlib
src = open(sys.argv[1]).read()
m = type(sys)("vw"); m.__dict__["__name__"] = "vw"
exec(compile(src, "variant-watch", "exec"), m.__dict__)

ok = fail = 0
def check(cond, msg):
    global ok, fail
    if cond: print("  ok:   " + msg); ok += 1
    else:    print("  FAIL: " + msg); fail += 1

# --- name matching. The first run announced hy4962/Share as a variant of tencent/Hy4-preview,
# because HF search is a substring search and "Hy4" is inside "hy4962".
w = {t for t in m.name_tokens("tencent/Hy4-preview") if t != "preview"}
check(not m.shares_family("hy4962/Share", w), "a repo merely CONTAINING the token is not a variant")
check(m.shares_family("tencent/Hy4-mini", w), "a real smaller sibling IS matched")
check(m.shares_family("mlx-community/Hy4-preview-4bit", w), "a quant of the same model is matched")
check(not m.shares_family("meta-llama/Llama-5-8B", w), "an unrelated model is not matched")

# --- the API budget. These are the three defences against re-tripping the rate limit.
calls = []
def spy(path):
    calls.append(path); raise RuntimeError("no network in test")
m.api = spy

cache = {"org/Cached-9B": [19_000_000_000, 4]}
calls.clear()
got = m.weight_bytes("org/Cached-9B", cache)
check(got == (19_000_000_000, 4) and not calls, "a cached size costs no API call")

calls.clear()
with contextlib.redirect_stderr(io.StringIO()) as err:
    got = m.weight_bytes("org/Never-Seen", cache)
# RED CONTROL. Without it the line above passes for a function that never calls the network at
# all, which would make the cache assertion meaningless.
check(len(calls) == 1, "RED control: an uncached size DOES cost exactly one API call")
check("org/Never-Seen" not in cache,
      "a FAILED lookup is not cached as empty — otherwise a rate-limited real model is marked "
      "weightless forever")
check("size lookup failed" in err.getvalue(), "a failed lookup is reported on stderr, not swallowed")

check(m.MAX_LOOKUPS <= 100, "there is a per-run ceiling on lookups (%d)" % m.MAX_LOOKUPS)
check(m.MIN_MODEL_GB >= 1.0, "there is a floor below which a repo is not a model (%.1f GB)" % m.MIN_MODEL_GB)

# --- the token. Authenticated calls are what keep this off the unauthenticated IP limit.
os.environ["HF_TOKEN"] = "t"
check(m.hf_token() == "t", "a token in the environment is used")
del os.environ["HF_TOKEN"]
os.environ.pop("HUGGING_FACE_HUB_TOKEN", None)
check(m.hf_token() is None or os.path.isfile(os.path.expanduser("~/.cache/huggingface/token")),
      "no token configured yields None rather than an invented value")

print("PYCOUNT %d %d" % (ok, fail))
PY
) > "$OUT" 2>&1
res=$?
cat "$OUT"

# THE EXIT CODE MUST TELL THE TRUTH. Written first without this, the script printed FAIL lines
# and still exited 0 — a silent-pass gate, which is the exact thing the test doctrine forbids.
# The counts are parsed back out and a missing count line is itself a failure, so a python
# crash before the summary cannot masquerade as a clean run.
counts="$(grep '^PYCOUNT ' "$OUT" | tail -1)"
if [ -z "$counts" ]; then
  fail "the python assertions did not reach their summary — treat as failed, not passed"
elif [ "$res" -ne 0 ]; then
  fail "the python assertion block exited $res"
else
  ok=$(( ok + $(echo "$counts" | cut -d" " -f2) ))
  failed=$(( failed + $(echo "$counts" | cut -d" " -f3) ))
fi
rm -f "$OUT"

printf '== test-variant-watch.sh: %d ok, %d failed\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
