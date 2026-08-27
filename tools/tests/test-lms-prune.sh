#!/usr/bin/env bash
# test-lms-prune.sh — a tool that runs `rm -rf` over ssh must never propose the wrong model.
#
# Every assertion runs the real script with its ssh and database seams replaced by stubs, so
# nothing here can reach the M5 and nothing can delete anything. The stub ssh records the
# commands it was given, which is how the --apply assertions check by effect rather than by
# reading the plan text back.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
. ./lib.sh
TOOL="$HOME/svnCheckouts/js-db-ad-astra/tools/ambrosio/lms-prune"
[ -f "$TOOL" ] || { fail "lms-prune missing at $TOOL"; finish; exit 1; }
need python3 "install python3"
need sqlite3 "brew install sqlite"

# --- stub ssh -------------------------------------------------------------------------------
# The tool shells out to `ssh`. Putting a stub first on PATH is the seam. It answers the two
# commands the tool issues (lms ls --json, the server-log scan) and logs everything else,
# which is how an unexpected rm shows up as a failed assertion instead of a real deletion.
mkdir -p "$SB/bin"
SSHLOG="$SB/ssh.log"
cat > "$SB/bin/ssh" <<'SHIM'
#!/usr/bin/env bash
cmd="${@: -1}"
echo "$cmd" >> "$SSHLOG"
case "$cmd" in
  *"ls --json"*) cat "$FIXDIR/models.json";;
  *server-logs*) cat "$FIXDIR/serverlogs.tsv";;
  *"rm -rf"*) exit 0;;
  *) : ;;
esac
SHIM
chmod +x "$SB/bin/ssh"
export SSHLOG
FIX="$SB/fix"; mkdir -p "$FIX"; export FIXDIR="$FIX"

# 100GB hot model, 100GB cold model, 100GB never-seen model, 10GB keep-listed model.
cat > "$FIX/models.json" <<'JSON'
[{"modelKey":"hot-model","path":"org/hot-model","sizeBytes":107374182400},
 {"modelKey":"cold-model","path":"org/cold-model","sizeBytes":107374182400},
 {"modelKey":"ghost-model","path":"org/ghost-model","sizeBytes":107374182400},
 {"modelKey":"qwen3-coder-next","path":"org/qwen3-coder-next","sizeBytes":10737418240},
 {"modelKey":"qwen3-coder-next-base-mlx","path":"org/qwen3-coder-next-base","sizeBytes":10737418240}]
JSON
# LM Studio server-log scan output: "<date>\t<model>". cold-model is old, hot-model is today.
TODAY="$(date +%Y-%m-%d)"
printf '2026-01-02\tcold-model\n%s\thot-model\n2026-01-02\tqwen3-coder-next-base-mlx\n' "$TODAY" > "$FIX/serverlogs.tsv"

DB="$SB/storage.sqlite"
sqlite3 "$DB" "CREATE TABLE usage_history (model TEXT, timestamp TEXT);
INSERT INTO usage_history VALUES ('hot-model','${TODAY}T10:00:00Z'),('cold-model','2026-01-02T10:00:00Z');"

KEEP="$SB/keeplist.txt"; printf '# comment\nqwen3-coder-next\n' > "$KEEP"

run() { PATH="$SB/bin:$PATH" python3 "$TOOL" --db "$DB" --keeplist "$KEEP" --host testhost "$@" 2>&1; }

# 1. The cold model is proposed and the hot one is not.
out="$(run --budget-gb 150)"
case "$out" in *"EVICT  cold-model"*) pass "cold model proposed for eviction";; *) fail "cold model not proposed: $out";; esac
case "$out" in *"EVICT  hot-model"*) fail "HOT model proposed — used today: $out";; *) pass "hot model never proposed";; esac

# 2. RED CONTROL. Under budget must propose nothing at all. Without this, assertion 1 would
#    pass for a tool that evicts everything it sees.
out="$(run --budget-gb 9000)"
case "$out" in
  *"nothing proposed"*) pass "RED control: under budget proposes nothing";;
  *) fail "RED control failed — proposed evictions while under budget: $out";;
esac

# 3. THE KEEP-LIST WINS. qwen3-coder-next must be protected even at an absurd budget.
out="$(run --budget-gb 1)"
case "$out" in *"EVICT  qwen3-coder-next "*|*"EVICT  qwen3-coder-next"$'\n'*) fail "keep-listed model proposed: $out";; esac
case "$out" in *"qwen3-coder-next (keeplist)"*) pass "keep-list protects its model at any budget";; *) fail "keep-list not applied: $out";; esac

# 4. THE SUBSTRING BUG. A keep-list entry for qwen3-coder-next must NOT protect
#    qwen3-coder-next-base-mlx, a different model. Found live 2026-08-26.
out="$(run --budget-gb 1)"
case "$out" in
  *"qwen3-coder-next-base-mlx (keeplist)"*) fail "substring match protected a different model: $out";;
  *) pass "keep-list does not protect a longer name that merely contains the entry";;
esac

# 5. NEVER-SEEN MODELS ARE HELD BACK, not sorted oldest-first. For an rm -rf tool an
#    unmatched id must not become the top candidate.
out="$(run --budget-gb 1)"
case "$out" in *"EVICT  ghost-model"*) fail "model with no history was proposed without --include-unused: $out";; esac
case "$out" in *"NO request history and are held back"*) pass "unknown-history models are held back";; *) fail "no held-back notice: $out";; esac

# 6. --include-unused lets them in, or the flag is decorative.
out="$(run --budget-gb 1 --include-unused)"
case "$out" in *"EVICT  ghost-model"*) pass "--include-unused admits models with no history";; *) fail "--include-unused had no effect: $out";; esac

# 7. NO DELETION WITHOUT --apply. By effect: the ssh log must carry no rm.
: > "$SSHLOG"
run --budget-gb 150 >/dev/null
if grep -q "rm -rf" "$SSHLOG"; then fail "dry run issued rm -rf"; else pass "dry run issues no rm (checked in the ssh log)"; fi

# 8. --apply deletes exactly the proposed model, and only under the models root.
: > "$SSHLOG"
run --budget-gb 150 --apply >/dev/null
if grep -q 'rm -rf .*org/cold-model' "$SSHLOG"; then pass "--apply removes the proposed model"; else fail "--apply did not issue the rm: $(cat "$SSHLOG")"; fi
if grep -q 'rm -rf .*org/hot-model' "$SSHLOG"; then fail "--apply removed the HOT model"; else pass "--apply left the hot model alone"; fi

# 9. RED CONTROL. An unreachable host must refuse to plan, not report an empty host.
cat > "$SB/bin/ssh" <<'SHIM'
#!/usr/bin/env bash
exit 255
SHIM
chmod +x "$SB/bin/ssh"
PATH="$SB/bin:$PATH" python3 "$TOOL" --db "$DB" --keeplist "$KEEP" --host testhost >/dev/null 2>&1
[ $? -eq 2 ] && pass "RED control: unreachable host exits 2 rather than planning" || fail "unreachable host did not refuse"

# Restore the working stub. Assertion 9 replaced it with a hard failure and everything after
# it inherited that — assertion 11 reported "ancestor path not refused" when the tool had in
# fact refused to plan at all. A test that leaves a broken seam behind makes every later
# assertion a measurement of the seam.
cat > "$SB/bin/ssh" <<'SHIM'
#!/usr/bin/env bash
cmd="${@: -1}"
echo "$cmd" >> "$SSHLOG"
case "$cmd" in
  *"ls --json"*) cat "$FIXDIR/models.json";;
  *server-logs*) cat "$FIXDIR/serverlogs.tsv";;
  *"rm -rf"*) exit 0;;
  *) : ;;
esac
SHIM
chmod +x "$SB/bin/ssh"

# 10. SHELL INJECTION. A model path carrying a quote must never reach the remote shell as
#     syntax. The stub records the exact command; a broken-out quote shows up as a second
#     command in the log. Found by a convocation panel on 2026-08-26.
cat > "$FIX/models.json" <<'JSON'
[{"modelKey":"evil","path":"org/evil\"; touch /tmp/astra-pwned; echo \"","sizeBytes":107374182400},
 {"modelKey":"hot-model","path":"org/hot-model","sizeBytes":107374182400}]
JSON
rm -f /tmp/astra-pwned
: > "$SSHLOG"
run --budget-gb 1 --include-unused --apply >/dev/null 2>&1
[ -f /tmp/astra-pwned ] && fail "SHELL INJECTION: a quoted model path executed a second command" || pass "a model path containing a quote does not break out of the rm"

# 11. A MODEL DIRECTORY THAT CONTAINS ANOTHER MODEL must be refused, not deleted. rm -rf on a
#     parent takes its children silently, including protected ones.
cat > "$FIX/models.json" <<'JSON'
[{"modelKey":"parent","path":"org/nest","sizeBytes":107374182400},
 {"modelKey":"child","path":"org/nest/inner","sizeBytes":1073741824}]
JSON
: > "$SSHLOG"
out="$(run --budget-gb 1 --include-unused --apply)"
case "$out" in *"REFUSED parent"*) pass "a model whose directory contains another is refused";; *) fail "ancestor path not refused: $out";; esac
if grep -q 'rm -rf .*org/nest' "$SSHLOG"; then fail "issued rm on a directory containing another model"; else pass "no rm issued for the containing directory"; fi

finish
