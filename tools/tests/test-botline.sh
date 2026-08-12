#!/usr/bin/env bash
# test-botline.sh — botline's routing, watermark, ordering, and schd-silence contracts, run
# against the REAL botline script with a recorded imsg transport. The `imsg` shim replays the
# exact JSONL shape live `imsg history --json` produced on 2026-08-12 (id / text / is_from_me /
# created_at) and records `imsg send` argv instead of texting Jonathan's actual phone — the one
# seam faked, so a test run doesn't message a human. Everything downstream is the shipped code.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
BOTLINE="$HERE/../botline/botline"
need python3 "xcode-select --install"

# ---- imsg shim, injected via IMSG_BIN (botline re-prepends system PATH internally, so a PATH
# shim can never win — the injectable-binary seam is the supported way to swap the transport) ----
mkdir -p "$SB/bin"
cat > "$SB/bin/imsg" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  send)    printf '%s\n' "$*" >> "$IMSG_SEND_LOG"; exit 0 ;;
  history) cat "$IMSG_FIXTURE"; exit 0 ;;
  *) exit 1 ;;
esac
SHIM
chmod +x "$SB/bin/imsg"
export IMSG_BIN="$SB/bin/imsg"
export IMSG_SEND_LOG="$SB/sends.log"; : > "$IMSG_SEND_LOG"
export BOTLINE_HOME="$SB/botline-home"

# ---- register / send (send asserted at the transport boundary, not by echo text) ----
assert_rc 0 "register creates a bot" "$BOTLINE" register --name testbot
assert_dir "$BOTLINE_HOME/inbox/testbot" "inbox dir exists after register"
assert_rc 0 "send succeeds" "$BOTLINE" send --from testbot "hello jonathan"
assert_contains "$IMSG_SEND_LOG" "[testbot] hello jonathan" "send reached imsg tagged with the bot name"
assert_eq "testbot" "$(cat "$BOTLINE_HOME/last_bot")" "send marked testbot as last-to-message"
red "send without --from must fail" "$BOTLINE" send "orphan text"

# ---- dispatch first run: seeds watermark, SILENT on stdout (schd pokes on any stdout) ----
export IMSG_FIXTURE="$SB/empty.jsonl"; : > "$IMSG_FIXTURE"
out="$("$BOTLINE" dispatch 2>"$SB/d1.err")"; rc=$?
assert_eq "0" "$rc" "first dispatch exits 0"
assert_empty "$out" "first dispatch stdout is empty (schd silence contract)"
assert_file "$BOTLINE_HOME/watermark_iso" "watermark seeded"

# ---- dispatch routing: @bot beats reply-to-last; is_from_me and empty text are skipped ----
"$BOTLINE" register --name ambrosio >/dev/null
cat > "$SB/replies.jsonl" <<'EOF'
{"id":101,"text":"@ambrosio pull the new model","is_from_me":false,"created_at":"2026-08-12T21:00:01+00:00"}
{"id":102,"text":"this one goes to the last bot","is_from_me":false,"created_at":"2026-08-12T21:00:02+00:00"}
{"id":103,"text":"my own outbound must not route","is_from_me":true,"created_at":"2026-08-12T21:00:03+00:00"}
{"id":104,"text":"","is_from_me":false,"created_at":"2026-08-12T21:00:04+00:00"}
EOF
export IMSG_FIXTURE="$SB/replies.jsonl"
out="$("$BOTLINE" dispatch 2>"$SB/d2.err")"; rc=$?
assert_eq "0" "$rc" "routing dispatch exits 0"
assert_empty "$out" "routing dispatch stdout STILL empty even when messages routed"
assert_file "$BOTLINE_HOME/inbox/ambrosio/101.msg" "@ambrosio message landed in ambrosio's inbox"
assert_contains "$BOTLINE_HOME/inbox/ambrosio/101.msg" "pull the new model" "@-prefix stripped, body kept"
assert_file "$BOTLINE_HOME/inbox/testbot/102.msg" "un-@'d reply routed to last bot (testbot)"
assert_no_file "$BOTLINE_HOME/inbox/testbot/103.msg" "outbound (is_from_me) not routed"
assert_eq "102" "$(cat "$BOTLINE_HOME/watermark_id")" "watermark advanced to highest routed id"

# ---- RED control: replaying the same fixture must route NOTHING (watermark dedup).
# Sentinel content, not file count — a replay would OVERWRITE 102.msg with the original
# body and the count would still read 1, so counting can't go red. ----
echo "SENTINEL-UNTOUCHED" > "$BOTLINE_HOME/inbox/testbot/102.msg"
"$BOTLINE" dispatch >/dev/null 2>&1
assert_contains "$BOTLINE_HOME/inbox/testbot/102.msg" "SENTINEL-UNTOUCHED" "replay did not re-route/overwrite an already-routed message"

# ---- @-target is a name, not a path: path-shaped targets fall back to reply-to-last ----
cat > "$SB/traversal.jsonl" <<'EOF'
{"id":201,"text":"@../../escaped hello there","is_from_me":false,"created_at":"2026-08-12T21:10:01+00:00"}
EOF
export IMSG_FIXTURE="$SB/traversal.jsonl"
"$BOTLINE" dispatch >/dev/null 2>&1
assert_no_file "$SB/escaped" "path-shaped @-target did not escape the inbox tree (inbox/../../ = \$SB)"
assert_file "$BOTLINE_HOME/inbox/testbot/201.msg" "path-shaped @-target fell back to reply-to-last"

# ---- a broken transport must be LOUD (stdout pokes the channel), never 'no new replies' ----
cat > "$SB/bin/imsg-broken" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = "history" ] && { echo "imsg: cannot open chat.db" >&2; exit 1; }
exit 0
SHIM
chmod +x "$SB/bin/imsg-broken"
out="$(IMSG_BIN="$SB/bin/imsg-broken" "$BOTLINE" dispatch 2>/dev/null)"; rc=$?
assert_eq "1" "$rc" "dispatch exits nonzero when the transport is broken"
assert_nonempty "$out" "broken transport announces itself on stdout (schd poke fires)"

# ---- recv ordering across a digit-length boundary (ids 9 vs 10 — byte order would flip them) ----
rm -f "$BOTLINE_HOME/inbox/testbot/"*.msg
echo "ninth" > "$BOTLINE_HOME/inbox/testbot/9.msg"
echo "tenth" > "$BOTLINE_HOME/inbox/testbot/10.msg"
got="$("$BOTLINE" recv --as testbot)"; rc=$?
assert_eq "0" "$rc" "recv exits 0 on successful delivery (rc was inverted once)"
assert_eq "ninth tenth" "$(printf '%s' "$got" | tr '\n' ' ' | xargs)" "recv delivers in message-id order (9 before 10)"
n="$(ls "$BOTLINE_HOME/inbox/testbot/"*.msg 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$n" "recv cleared the inbox"

# ---- delivery failure must PRESERVE messages (undelivered + rm'd = unrecoverable loss).
# Deterministic EPIPE on macOS (no /dev/full here): the reader takes ONE line of a >64KB
# message and closes, so recv's cat blocks on the fifo, then dies mid-message — guaranteed
# to fail while both messages are still on disk. ----
# 300 lines × 1KB: head -n 1 takes only line 1 then closes, and the remaining ~299KB
# overflows the 64KB fifo buffer, so cat reliably dies mid-message
python3 -c "print(('x'*1000+'\n')*300, end='')" > "$BOTLINE_HOME/inbox/testbot/20.msg"
echo "precious" > "$BOTLINE_HOME/inbox/testbot/21.msg"
mkfifo "$SB/fifo"
( head -n 1 < "$SB/fifo" > /dev/null ) &
"$BOTLINE" recv --as testbot > "$SB/fifo" 2>/dev/null; rc=$?
wait
[ "$rc" -ne 0 ] && pass "recv exits nonzero when delivery fails (rc=$rc)" || fail "recv exited 0 despite failed delivery"
assert_file "$BOTLINE_HOME/inbox/testbot/20.msg" "interrupted message KEPT after failed delivery"
assert_file "$BOTLINE_HOME/inbox/testbot/21.msg" "queued message behind it KEPT too"
rm -f "$BOTLINE_HOME/inbox/testbot/"*.msg
red "recv with a path-shaped bot name must fail" "$BOTLINE" recv --as ../escaped
red "register with a path-shaped bot name must fail" "$BOTLINE" register --name ../evil

# ---- recv --peek keeps messages ----
echo "keepme" > "$BOTLINE_HOME/inbox/testbot/11.msg"
"$BOTLINE" recv --as testbot --peek >/dev/null
assert_file "$BOTLINE_HOME/inbox/testbot/11.msg" "--peek left the message in place"

# ---- broken transport JSON must not crash dispatch (schd job must survive) ----
printf 'not json at all\n{"id":' > "$SB/broken.jsonl"
export IMSG_FIXTURE="$SB/broken.jsonl"
assert_rc 0 "dispatch survives broken JSONL with rc 0" "$BOTLINE" dispatch

finish
