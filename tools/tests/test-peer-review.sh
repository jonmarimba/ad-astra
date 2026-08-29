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
# Keep a copy of the task the reviewer was handed. The value of the task is in what the reviewer
# READS, so asserting on the argv alone cannot see whether the content is right.
prev=""
for a in "$@"; do
  [ "$prev" = "--message-file" ] && [ -f "$a" ] && cp "$a" "${TASKCAP:-/dev/null}"
  prev="$a"
done
case "${STUB_MODE:-clean}" in
  clean)   printf '{"status":"ok","result":{"payloads":[{"text":"NO DEFECTS FOUND"}]}}';;
  finding) printf '{"status":"ok","result":{"payloads":[{"text":"- line 3: unquoted path"}]}}';;
  nullres) printf '{"status":"ok","result":null}';;
  garbage) printf 'not json';;
  crash)   exit 7;;
esac
SHIM
chmod +x "$STUB"; export ARGLOG
TASKCAP="$SB/taskcap"; export TASKCAP

run(){ REVIEWER_BIN="$STUB" WORKLOG_BIN=/nonexistent "$TOOL" --repo "$REPO" "$@" 2>&1; }
ref(){ git -C "$REPO" rev-parse -q --verify refs/peer-review/last 2>/dev/null || echo NONE; }
# A failure case leaves the ref parked on the commit it could not review — correctly, so it is
# retried. Each later case therefore has to clear the parking brake, or it measures the
# previous case's stuck commit instead of its own.
unstick(){ git -C "$REPO" update-ref refs/peer-review/last "$(git -C "$REPO" rev-parse HEAD)"; }
# ...and then give the next case something of its own to review, or it measures an empty run.
fresh(){ echo "$RANDOM" >> "$REPO/a.txt"; git -C "$REPO" commit -qam "commit for $1"; }

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
# The token alone is not enough: `--agent --session-key ...` still contains "--agent" and is
# exactly the regression that would break the real CLI while this assertion passed. The FIRST
# attempt at this fix was also wrong — [A-Za-z0-9_-]+ includes the dash, so it happily read
# "--session-key" as the agent value. The reviewer caught the broken fix on the next pass.
# The value must not start with a dash.
grep -qE -- "--agent +[A-Za-z0-9_][A-Za-z0-9_-]*" "$ARGLOG" && pass "invocation passes --agent WITH a value" || fail "--agent has no value: $(cat "$ARGLOG")"
grep -q -- "--session-key" "$ARGLOG" && pass "invocation passes --session-key (keeps review out of the reviewer's own session)" || fail "--session-key missing"

# 3. A CLEAN REVIEW IS SILENT and advances the ref. Silence is the healthy state; the schedule
#    pokes the author only on non-empty output.
[ -z "$out" ] && pass "a clean review prints nothing" || fail "clean review was not silent: $out"
[ "$(ref)" = "$(git -C "$REPO" rev-parse HEAD)" ] && pass "clean review advances the ref" || fail "ref did not advance after a clean review"

# 3b. THE TASK TELLS THE REVIEWER WHAT HAS MOVED SINCE THE COMMIT. Review runs behind the author
#     by construction, and on 2026-08-28 several findings arrived against code already fixed or a
#     file already deleted — accurate about the commit and spent on nothing.
if [ -f "$TASKCAP" ]; then
  grep -q "staleness of this commit" "$TASKCAP" \
    && pass "the task tells the reviewer which files have moved since the commit" \
    || fail "no staleness section in the task the reviewer was handed"
  grep -q "every file in this commit is unchanged at HEAD" "$TASKCAP" \
    && pass "RED control: an unchanged commit says so explicitly rather than listing nothing" \
    || fail "an unchanged commit produced no staleness verdict at all"
else
  fail "could not capture the task file to check it"
fi

# 3c. A COMMITTED FILENAME WITH A SPACE IS ONE FILE. The first version word-split the output of
#     git show --name-only, so "docs/review notes.md" became two names, both reported missing,
#     and the reviewer was told a confident lie about what had changed.
mkdir -p "$REPO/docs"
printf 'x\n' > "$REPO/docs/review notes.md"
git -C "$REPO" add "docs/review notes.md" && git -C "$REPO" commit -qm "a file with a space in its name"
rm -f "$TASKCAP"
STUB_MODE=clean run >/dev/null
if [ -f "$TASKCAP" ]; then
  grep -q "docs/review notes.md" "$TASKCAP" && pass "a filename containing a space is kept whole" \
    || fail "the spaced filename was split or lost: $(grep -A3 staleness "$TASKCAP" | head -4)"
  grep -q "^  docs/review\$" "$TASKCAP" && fail "the filename was word-split into pieces" \
    || pass "RED control: no half-filename appears in the task"
else
  fail "could not capture the task file"
fi

# 3d. THE NET SAYS WHEN IT IS FALLING BEHIND. A backlog is invisible by construction — every
#     individual run looks like it worked — and on 2026-08-28 thirty-four commits accumulated
#     against a limit of three per run with nothing anywhere reporting it.
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13; do echo "b$n" >> "$REPO/a.txt"; git -C "$REPO" commit -qam "backlog $n"; done
# THREE RUNS, because the warning needs three measurements before it will claim a trend — it
# used to fire off a single prior reading and announce a three-run window it had not observed.
# STUB_MODE=crash keeps the ref parked so the backlog stays flat across them, which is the
# condition the warning exists to report: a queue that is not improving.
# Three PRIMING runs, then a fourth to assert: the check reads its history before appending to
# it, so three prior measurements exist only from the fourth run onwards. Getting that boundary
# wrong is how the warning came to claim a three-run trend off a single reading in the first
# place, so the test states it explicitly rather than counting runs by feel.
STUB_MODE=crash run --limit 3 >/dev/null 2>&1
STUB_MODE=crash run --limit 3 >/dev/null 2>&1
STUB_MODE=crash run --limit 3 >/dev/null 2>&1
out="$(STUB_MODE=crash run --limit 3 2>&1)"
case "$out" in *"commits behind review"*) pass "a flat backlog beyond three runs' worth is reported";;
  *) fail "a flat 13-commit backlog was not reported after three runs: $out";; esac
# RED CONTROL: one run alone must NOT claim a three-run trend.
git -C "$REPO" update-ref -d "refs/peer-review/backlog/$(basename "$REPO")" 2>/dev/null || true
out="$(STUB_MODE=crash run --limit 3 2>&1)"
case "$out" in *"commits behind review"*) fail "claimed a three-run trend from a single run";;
  *) pass "RED control: one run does not claim a three-run trend";; esac
STUB_MODE=crash run --limit 3 >/dev/null 2>&1
STUB_MODE=crash run --limit 3 >/dev/null 2>&1
# RED CONTROL: once drained, it must go quiet, or the warning is permanent noise.
while [ "$(git -C "$REPO" rev-list --count refs/peer-review/last..HEAD)" -gt 0 ]; do
  STUB_MODE=clean run --limit 10 >/dev/null
done
echo drained >> "$REPO/a.txt"; git -C "$REPO" commit -qam "one more"
out="$(STUB_MODE=clean run --limit 3)"
case "$out" in *"commits behind review"*) fail "still warning with a 1-commit backlog";;
  *) pass "RED control: a drained queue stops warning";; esac

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

unstick; fresh nullres
# 7. A NULL RESULT IS NOT A CLEAN REVIEW. Found by the reviewer itself on 2026-08-27: the
#    parse raised, stderr was discarded, and an empty body read as "nothing found".
before="$(ref)"
out="$(STUB_MODE=nullres run)"
case "$out" in *"NOT advancing the ref"*) pass "a null result reports the commit as unreviewed";;
  *) fail "null result passed as a clean review: $out";; esac
# REPORTING IT IS NOT ENOUGH. The first version said "NOT reviewed" and advanced the ref
# anyway, so nothing ever looked at that commit again — which makes the review-after guarantee
# in AGENTS.md false. The reviewer caught the contradiction between the rule and the code.
[ "$(ref)" = "$before" ] && pass "an unreadable answer leaves the ref alone so the commit is retried" || fail "ref advanced past a commit whose review could not be read"

unstick; fresh garbage
# 8. NON-JSON IS NOT A CLEAN REVIEW EITHER.
before="$(ref)"
out="$(STUB_MODE=garbage run)"
case "$out" in *"NOT advancing the ref"*) pass "non-JSON output reports the commit as unreviewed";;
  *) fail "garbage output passed as a clean review: $out";; esac
[ "$(ref)" = "$before" ] && pass "non-JSON output leaves the ref alone too" || fail "ref advanced past unparseable output"

unstick
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
