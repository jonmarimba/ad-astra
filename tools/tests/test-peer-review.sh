#!/usr/bin/env bash
# test-peer-review.sh — the review loop must never silently skip a commit.
#
# This tool is the mechanism that makes "act without asking" safe: work is committed, the other
# assistant reviews the commit, the finding lands in the author's next scheduler poke. Every
# failure mode here is the same shape — a commit that looks reviewed and was not — so most of
# these assertions are about the git ref, which is the only thing that remembers.
#
# The reviewer is stubbed. Nothing here invokes the real assistant or touches a real repo.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/../peer-review/peer-review"
SB="$(mktemp -d)"
ok=0; failed=0
pass(){ printf '  ok:   %s\n' "$1"; ok=$((ok+1)); }
fail(){ printf '  FAIL: %s\n' "$1"; failed=$((failed+1)); }
[ -x "$TOOL" ] || { fail "peer-review missing or not executable at $TOOL"; exit 1; }

# --- a real git repo to review -------------------------------------------------------------
REPO="$SB/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q . && git config user.email t@t && git config user.name t
echo one > a.txt && git add . && git commit -qm "first commit"

# --- stub reviewer. Records its argv so the assertions can check the invocation by effect. --
STUB="$SB/reviewer"; ARGLOG="$SB/argv.log"
cat > "$STUB" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ARGLOG"
case "${STUB_MODE:-clean}" in
  clean)   printf '{"status":"ok","result":{"payloads":[{"text":"NO DEFECTS FOUND"}]}}';;
  finding) printf '{"status":"ok","result":{"payloads":[{"text":"- line 3: unquoted path"}]}}';;
  nullres) printf '{"status":"ok","result":null}';;
  garbage) printf 'not json';;
  crash)   exit 7;;
esac
SHIM
chmod +x "$STUB"; export ARGLOG

run(){ REVIEWER_BIN="$STUB" WORKLOG_BIN=/nonexistent "$TOOL" --repo "$REPO" "$@" 2>&1; }
ref(){ git -C "$REPO" rev-parse -q --verify refs/peer-review/last 2>/dev/null || echo NONE; }

# 1. FIRST RUN SETS A BASELINE AND REVIEWS NOTHING. Otherwise installing the tool floods the
#    reviewer with every commit in history.
out="$(run)"
case "$out" in *baseline*) pass "first run records a baseline instead of reviewing history";;
  *) fail "no baseline on first run: $out";; esac
[ "$(ref)" = "$(git -C "$REPO" rev-parse HEAD)" ] && pass "baseline ref points at HEAD" || fail "baseline ref wrong"
[ -s "$ARGLOG" ] && fail "first run invoked the reviewer" || pass "first run does not invoke the reviewer"

# 2. A NEW COMMIT IS SENT, and the invocation carries the flags that make it work at all.
echo two >> a.txt && git -C "$REPO" commit -qam "second commit"
: > "$ARGLOG"
out="$(STUB_MODE=clean run)"
grep -q -- "--agent" "$ARGLOG" && pass "invocation passes --agent (without it the CLI exits 0 doing nothing)" || fail "--agent missing"
grep -q -- "--session-key" "$ARGLOG" && pass "invocation passes --session-key (keeps review out of the reviewer's own session)" || fail "--session-key missing"

# 3. A CLEAN REVIEW IS SILENT and advances the ref. Silence is the healthy state; the schedule
#    pokes the author only on non-empty output.
[ -z "$out" ] && pass "a clean review prints nothing" || fail "clean review was not silent: $out"
[ "$(ref)" = "$(git -C "$REPO" rev-parse HEAD)" ] && pass "clean review advances the ref" || fail "ref did not advance after a clean review"

# 4. A FINDING REACHES STDOUT. This is the whole delivery path — stdout becomes a scheduler
#    poke at the author. A finding written only to a file is the backlog nobody clears.
echo three >> a.txt && git -C "$REPO" commit -qam "third commit"
out="$(STUB_MODE=finding run)"
case "$out" in *"unquoted path"*) pass "a finding is printed to stdout, where the scheduler will surface it";;
  *) fail "finding did not reach stdout: $out";; esac

# 5. RED CONTROL. Without this, assertion 3 passes for a tool that never prints anything at all.
case "$out" in *"NO DEFECTS FOUND"*) fail "RED control: printed the clean marker as if it were a finding";;
  *) pass "RED control: the clean marker is not itself reported";; esac

# 6. A REVIEWER THAT CRASHES MUST NOT ADVANCE THE REF. Otherwise the commit is never reviewed
#    by anything, ever, and nothing says so.
echo four >> a.txt && git -C "$REPO" commit -qam "fourth commit"
before="$(ref)"
out="$(STUB_MODE=crash run)"
[ "$(ref)" = "$before" ] && pass "a crashed reviewer leaves the ref alone so the commit is retried" || fail "ref advanced past a commit the reviewer never reviewed"
case "$out" in *failed*) pass "a crashed reviewer says so out loud";; *) fail "crash was silent: $out";; esac

# 7. A NULL RESULT IS NOT A CLEAN REVIEW. Found by the reviewer itself on 2026-08-27: the
#    parse raised, stderr was discarded, and an empty body read as "nothing found".
out="$(STUB_MODE=nullres run)"
case "$out" in *"NOT reviewed"*) pass "a null result reports the commit as unreviewed";;
  *) fail "null result passed as a clean review: $out";; esac

# 8. NON-JSON IS NOT A CLEAN REVIEW EITHER.
echo five >> a.txt && git -C "$REPO" commit -qam "fifth commit"
out="$(STUB_MODE=garbage run)"
case "$out" in *"NOT reviewed"*) pass "non-JSON output reports the commit as unreviewed";;
  *) fail "garbage output passed as a clean review: $out";; esac

# 9. --limit BOUNDS A RUN, and what it leaves behind is picked up next time rather than lost.
for n in 6 7 8; do echo $n >> a.txt; git -C "$REPO" commit -qam "commit $n"; done
: > "$ARGLOG"
STUB_MODE=clean run --limit 2 >/dev/null
[ "$(wc -l < "$ARGLOG" | tr -d ' ')" = "2" ] && pass "--limit bounds how many commits go out in one run" || fail "--limit not honoured: $(wc -l < "$ARGLOG") sent"
: > "$ARGLOG"
STUB_MODE=clean run --limit 2 >/dev/null
[ "$(wc -l < "$ARGLOG" | tr -d ' ')" -ge 1 ] && pass "commits left over by --limit are picked up on the next run" || fail "leftover commits were skipped"

# 10. RED CONTROL. A missing reviewer binary must fail loudly, not report a quiet clean sweep.
REVIEWER_BIN=/nonexistent "$TOOL" --repo "$REPO" >/dev/null 2>&1
[ $? -eq 2 ] && pass "RED control: a missing reviewer exits nonzero instead of reporting silence" || fail "missing reviewer did not fail"

printf '== test-peer-review.sh: %d ok, %d failed\n' "$ok" "$failed"
rm -rf "$SB"
[ "$failed" -eq 0 ]
