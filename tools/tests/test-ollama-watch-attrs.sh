#!/usr/bin/env bash
# test-ollama-watch-attrs.sh — ollama-watch must not go silent on things Jonathan wants told.
#
# THE FAILURE THIS GUARDS. On 2026-08-25 he found kimi-k3 himself by browsing ollama.com,
# having heard nothing from this watcher. Two defects produced the silence:
#   1. The watcher first ran 12 August against a library that already contained kimi-k3
#      (~29 July). Everything present went into seen.txt under "first run, no notify", so
#      k3 was born already-seen and could never alert.
#   2. The model later changed ACCESS TIER — 402 "extra usage only" on 6 August, serving on
#      the plan by the 25th. Name-only diffing cannot see that; the name never changed.
# Every assertion below is by effect on the tool's real output, against a stubbed transport,
# with a RED control proving the assertion can fail.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
. ./lib.sh
TOOL="$(cd ../../js-db-ad-astra/tools/ollama-watch 2>/dev/null && pwd)/ollama-watch"
[ -x "$TOOL" ] || TOOL="$HOME/svnCheckouts/js-db-ad-astra/tools/ollama-watch/ollama-watch"
[ -x "$TOOL" ] || { fail "ollama-watch not executable at $TOOL"; finish; exit 1; }
PARSER="$(dirname "$TOOL")/parse_model_attrs.py"
need python3 "install python3"

# ---------------------------------------------------------------------------
# Stub transport. $CURL_BIN is the tool's own injectable seam. The stub serves a
# library index and per-model pages out of a fixture dir, so no test touches the network
# and the whole thing is deterministic.
# ---------------------------------------------------------------------------
FIX="$SB/fixtures"; mkdir -p "$FIX"
STUB="$SB/curl-stub"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
# args end with the URL
url="${@: -1}"
case "$url" in
  */library) cat "$FIXDIR/library.html" 2>/dev/null;;
  */library/*) f="${url##*/library/}"; cat "$FIXDIR/$f.html" 2>/dev/null;;
  *) : ;;
esac
STUBEOF
chmod +x "$STUB"

mk_library() { : > "$FIX/library.html"; for m in "$@"; do echo "<a href=\"/library/$m\">$m</a>" >> "$FIX/library.html"; done; }
mk_page() { # name usage context size tags updated downloads
  cat > "$FIX/$1.html" <<EOF
<html><script>var junk="vision tools thinking cloud embedding";</script>
<body>$1 $7 Downloads Updated $6 ago $5 Usage $2 Context $3 tokens Size $4 parameters</body></html>
EOF
}

export FIXDIR="$FIX"
# BOTLINE MUST BE A STUB THAT EXISTS, NOT A MISSING PATH.
# notify() falls through to a REAL `imsg send` when $BOTLINE is not executable. Pointing it
# at /nonexistent therefore did not disable sending — it routed every non-dry-run assertion
# to Jonathan's actual phone, and he received two texts of fixture data at 01:05 on
# 2026-08-26 because of it. A test that can reach a human is not a test.
SENTLOG="$SB/sent.log"
cat > "$SB/botline-stub" <<'BLEOF'
#!/usr/bin/env bash
echo "STUB-SEND $*" >> "$SENTLOG"
BLEOF
chmod +x "$SB/botline-stub"
run_watch() {
  OLLAMA_WATCH_HOME="$1" CURL_BIN="$STUB" BOTLINE_BIN="$SB/botline-stub" \
  SENTLOG="$SENTLOG" FIXDIR="$FIX" JS_NUMBER="+10000000000" "$TOOL" "${@:2}" 2>&1
}

# ---------------------------------------------------------------------------
# 1. The parser must never invent capability tags out of JavaScript.
#    Every fixture page carries a <script> naming all five tags. A model whose body has
#    none must report none. This is the script-stripping bug, found 2026-08-26.
# ---------------------------------------------------------------------------
mk_page plainmodel "?" "?" "7b" "" "2 years" "500K"
attrs="$(cat "$FIX/plainmodel.html" | python3 "$PARSER")"
case "$attrs" in
  *vision*|*cloud*|*thinking*) fail "parser picked up tags from <script> — got: $attrs";;
  *) pass "parser ignores capability words inside <script>";;
esac

# ---------------------------------------------------------------------------
# 2. A fresh seed must NOT claim everything is known.
# ---------------------------------------------------------------------------
H1="$SB/h1"; mkdir -p "$H1"
mk_library kimi-k3 everythinglm
mk_page kimi-k3 "extra high" "1M" "2.81T" "vision tools thinking cloud" "4 weeks" "55.9K"
mk_page everythinglm "?" "?" "13b" "" "2 years" "561K"
out="$(run_watch "$H1" check --dry-run)"
case "$out" in
  *"run 'ollama-watch backfill'"*) pass "fresh seed points at backfill instead of going quiet";;
  *) fail "fresh seed did not mention backfill — got: $out";;
esac

# ---------------------------------------------------------------------------
# 3. backfill must surface a model that was present at seed time.
#    This is kimi-k3's exact situation and the reason he was never told.
# ---------------------------------------------------------------------------
out="$(run_watch "$H1" backfill --dry-run)"
assert_nonempty "$out" "backfill produced output"
case "$out" in
  *kimi-k3*) pass "backfill surfaces a model that existed before the watcher did";;
  *) fail "backfill did NOT surface kimi-k3 — got: $out";;
esac
# and it must NOT dump a two-year-old local model into the message
case "$out" in
  *"would notify"*everythinglm*) fail "backfill put a 2-year-old model in the notification";;
  *) pass "backfill keeps stale models out of the notification";;
esac

# ---------------------------------------------------------------------------
# 4. backfill is idempotent — a second run says nothing.
#    A watcher that repeats itself every four hours gets muted, which is the same
#    end state as saying nothing at all.
# ---------------------------------------------------------------------------
run_watch "$H1" backfill >/dev/null 2>&1
out="$(run_watch "$H1" backfill)"
case "$out" in
  *"nothing"*) pass "second backfill is silent (idempotent)";;
  *) fail "backfill repeated itself — got: $out";;
esac

# ---------------------------------------------------------------------------
# 5. THE TIER CHANGE. Same name, changed attributes, must alert.
#    kimi-k3 went from gated to plan-included without its name changing.
# ---------------------------------------------------------------------------
H2="$SB/h2"; mkdir -p "$H2"
mk_library kimi-k3
mk_page kimi-k3 "extra high" "1M" "2.81T" "vision tools thinking cloud" "4 weeks" "55.9K"
run_watch "$H2" check >/dev/null 2>&1          # seed
run_watch "$H2" backfill >/dev/null 2>&1       # announce, so the name diff is quiet
mk_page kimi-k3 "high" "1M" "2.81T" "vision tools thinking cloud" "4 weeks" "55.9K"   # tier moved
out="$(run_watch "$H2" check --dry-run)"
case "$out" in
  *Changed*kimi-k3*) pass "attribute change on an already-seen model fires an alert";;
  *) fail "tier change did NOT alert — got: $out";;
esac

# ---------------------------------------------------------------------------
# 6. RED CONTROL. With attributes UNCHANGED the same path must stay silent.
#    If this goes green, assertion 5 proves nothing — it would alert on anything.
# ---------------------------------------------------------------------------
run_watch "$H2" check >/dev/null 2>&1          # absorb the change above
out="$(run_watch "$H2" check --dry-run)"
case "$out" in
  *"no new frontier models"*) pass "RED control: unchanged attributes stay silent";;
  *) fail "RED control failed — alerted with nothing changed: $out";;
esac

# ---------------------------------------------------------------------------
# 7. RED CONTROL. An unreadable page must not read as a change.
#    Network hiccups must not manufacture alerts, or the channel gets muted.
# ---------------------------------------------------------------------------
: > "$FIX/kimi-k3.html"
out="$(run_watch "$H2" check --dry-run)"
case "$out" in
  *"no new frontier models"*) pass "RED control: unreadable page is not a change";;
  *) fail "RED control failed — empty page produced an alert: $out";;
esac

# ---------------------------------------------------------------------------
# 8. Nothing in this file may reach the real transport. If imsg was called, the stub
#    log will not account for the sends, and JS_NUMBER above is deliberately unroutable.
# ---------------------------------------------------------------------------
if [ -s "$SENTLOG" ]; then
  pass "sends went to the stub, not to a person ($(wc -l < "$SENTLOG" | tr -d ' ') captured)"
else
  fail "no sends captured — the stub was not exercised, so send-safety is unproven"
fi

# ---------------------------------------------------------------------------
# 9. A CHANGED DOWNLOAD COUNT IS NOT A CHANGE.
#    Download counters tick constantly and "9 hours ago" becomes "13 hours ago" on its
#    own. Diffing the whole attribute line therefore marks every model changed on every
#    run — that fired live at 07:43 on 2026-08-26 and texted Jonathan eighteen models
#    whose only difference was 397.1K downloads becoming 397.5K. Worse than the silence
#    it replaced, and the fastest way to get the channel muted.
# ---------------------------------------------------------------------------
H3="$SB/h3"; mkdir -p "$H3"
mk_library kimi-k3
mk_page kimi-k3 "extra high" "1M" "2.81T" "vision tools thinking cloud" "4 weeks" "55.9K"
run_watch "$H3" check >/dev/null 2>&1
run_watch "$H3" backfill >/dev/null 2>&1
mk_page kimi-k3 "extra high" "1M" "2.81T" "vision tools thinking cloud" "5 weeks" "61.2K"  # only churn
out="$(run_watch "$H3" check --dry-run)"
case "$out" in
  *"no new frontier models"*) pass "download count and age churn alone do NOT alert";;
  *) fail "churn-only change alerted — got: $out";;
esac

# ---------------------------------------------------------------------------
# 10. A THIN ROW MUST NOT FLAP.
#     Multi-size pages render inconsistently; `mixtral` alternated between "-" and
#     "tools" on consecutive live fetches. With usage, context and size all unknown,
#     tags alone are not enough to call it a change.
# ---------------------------------------------------------------------------
H4="$SB/h4"; mkdir -p "$H4"
mk_library mixtral
mk_page mixtral "?" "?" "?" "" "1 year" "1.9M"
run_watch "$H4" check >/dev/null 2>&1
run_watch "$H4" backfill >/dev/null 2>&1
mk_page mixtral "?" "?" "?" "tools" "1 year" "1.9M"   # tags appear out of nowhere
out="$(run_watch "$H4" check --dry-run)"
case "$out" in
  *"no new frontier models"*) pass "thin row (usage/context/size all unknown) does not flap";;
  *) fail "thin row flapped — got: $out";;
esac

finish
