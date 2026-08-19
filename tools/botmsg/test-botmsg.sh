#!/bin/bash
# test-botmsg.sh — routing is the whole tool, so routing is what gets tested.
#
# Sending was never the hard part; imsg already did it. The failure this exists
# to prevent is a bot reading a reply meant for another bot, which has really
# happened between GhOST-Claude and GhOST-OpenClaw on the shared thread. The
# mirror failure is just as bad: a reply nobody claims, silently dropped.
#
# imsg is faked throughout. A messaging test that texts a real phone is not a
# test — test-team-ghost-health.sh proved that on 2026-08-18 by sending Jonathan
# two fake alarms.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTMSG="$HERE/botmsg"
PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
need() { command -v "$1" >/dev/null 2>&1 || { echo "MISSING DEPENDENCY: $1"; exit 1; }; }
need python3

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export BOTMSG_STATE="$WORK/state"
export BOTMSG_TO="+15555550100"
export BOTMSG_IMSG_BIN="$WORK/fake-imsg"

# Fake imsg. Reads a transcript fixture and mimics the real tool's contract:
# newest-first JSON lines, is_from_me for outbound, reply_to_text when the human
# used the native reply gesture.
cat > "$WORK/fake-imsg" <<'FAKE'
#!/usr/bin/env python3
import json, os, sys
sub = sys.argv[1] if len(sys.argv) > 1 else ""
if sub == "chats":
    print(json.dumps({"id": 99, "identifier": os.environ["BOTMSG_TO"],
                      "is_group": False}))
elif sub == "history":
    for m in reversed(json.load(open(os.environ["FIXTURE"]))):
        print(json.dumps(m))
elif sub == "send":
    open(os.environ["SENTLOG"], "a").write(" ".join(sys.argv) + "\n")
elif sub == "--help":
    print("fake imsg")
else:
    sys.exit(2)
FAKE
chmod +x "$WORK/fake-imsg"
export SENTLOG="$WORK/sent.log"
export FIXTURE="$WORK/fixture.json"

# One shared thread. Two bots have spoken; the human has answered three times,
# each a different way.
cat > "$FIXTURE" <<'JSON'
[
 {"id": 10, "is_from_me": true,  "text": "[ghost-claude] build finished"},
 {"id": 11, "is_from_me": true,  "text": "[kicker-xo] deploy is green"},
 {"id": 12, "is_from_me": false, "text": "nice, ship it",
  "reply_to_text": "[ghost-claude] build finished"},
 {"id": 13, "is_from_me": false, "text": "[ghost-claude] what about the tests?"},
 {"id": 14, "is_from_me": false, "text": "ok thanks"}
]
JSON

echo "== 1. A native reply routes to the bot that was replied to =="
out="$("$BOTMSG" inbox --as ghost-claude --json)"
if echo "$out" | grep -q "nice, ship it" && echo "$out" | grep -q "native-reply"; then
  ok "native reply claimed by the right bot, by reply_to_text"
else
  bad "native reply not routed (got: $(echo "$out" | tr -d '\n' | head -c 160))"
fi

echo "== 2. That reply must NOT also be claimed by the other bot =="
out="$("$BOTMSG" inbox --as kicker-xo --json)"
if echo "$out" | grep -q "nice, ship it"; then
  bad "kicker-xo claimed a reply addressed to ghost-claude — this is the bug"
else
  ok "other bot did not claim it"
fi

echo "== 3. An explicitly tagged reply routes by its tag =="
rm -rf "$BOTMSG_STATE"
out="$("$BOTMSG" inbox --as ghost-claude --json)"
if echo "$out" | grep -q "what about the tests" && echo "$out" | grep -q "explicit-tag"; then
  ok "explicit [tag] claimed"
else
  bad "explicit tag not routed"
fi
out="$("$BOTMSG" inbox --as kicker-xo --json)"
if echo "$out" | grep -q "what about the tests"; then
  bad "wrong bot claimed an explicitly addressed message"
else
  ok "explicit tag not claimed by the other bot"
fi

echo "== 4. An unaddressed reply goes to whoever spoke last, and says it guessed =="
rm -rf "$BOTMSG_STATE"
out="$("$BOTMSG" inbox --as kicker-xo --json)"    # kicker-xo sent last (id 11)
if echo "$out" | grep -q "ok thanks" && echo "$out" | grep -q "guess"; then
  ok "bare reply went to the most recent sender, labelled a guess"
else
  bad "bare reply not routed to the last sender (got: $(echo "$out" | tr -d '\n' | head -c 160))"
fi
rm -rf "$BOTMSG_STATE"
out="$("$BOTMSG" inbox --as ghost-claude --json)"
if echo "$out" | grep -q "ok thanks"; then
  bad "a bot that did NOT speak last claimed the bare reply"
else
  ok "the other bot left the bare reply alone"
fi

echo "== 5. The watermark must not swallow another bot's mail =="
# ghost-claude reads first and advances. kicker-xo must STILL find its own
# message afterwards — the failure here is silent and permanent.
rm -rf "$BOTMSG_STATE"
"$BOTMSG" inbox --as ghost-claude --json >/dev/null
out="$("$BOTMSG" inbox --as kicker-xo --json)"
if echo "$out" | grep -q "ok thanks"; then
  ok "kicker-xo still received its message after another bot read first"
else
  bad "one bot's read consumed another bot's reply — silently lost"
fi

echo "== 6. A second read returns nothing new =="
out="$("$BOTMSG" inbox --as kicker-xo --json)"
if [ "$(echo "$out" | tr -d ' \n')" = "[]" ]; then
  ok "watermark advanced; no repeats"
else
  bad "re-reported an already-seen message: $out"
fi

echo "== 7. Sending tags the message with the bot id =="
: > "$SENTLOG"
"$BOTMSG" send --as kicker-xo --text "hello there" >/dev/null
if grep -q "\[kicker-xo\] hello there" "$SENTLOG"; then
  ok "outbound carries its tag, which is what makes replies routable"
else
  bad "outbound was not tagged: $(cat "$SENTLOG")"
fi

echo "== 8. No destination must refuse, not default to someone =="
out="$(env -u BOTMSG_TO "$BOTMSG" send --as x --text hi 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "no destination"; then
  ok "refused without a destination"
else
  bad "sent, or failed unclearly, with no destination configured (rc=$rc)"
fi

echo "== 9. Corrupt state must refuse, not replay the whole thread =="
mkdir -p "$BOTMSG_STATE"; echo 'not json' > "$BOTMSG_STATE/kicker-xo.json"
out="$("$BOTMSG" inbox --as kicker-xo --json 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "unreadable"; then
  ok "corrupt watermark refused"
else
  bad "corrupt state read as empty — every old instruction replays as new (rc=$rc)"
fi

echo "== 10. A read failure must be loud, never an empty inbox =="
cat > "$WORK/fake-imsg" <<'BROKEN'
#!/usr/bin/env python3
import sys
sys.stderr.write("chat.db is locked\n")
sys.exit(1)
BROKEN
chmod +x "$WORK/fake-imsg"
rm -rf "$BOTMSG_STATE"
out="$("$BOTMSG" inbox --as kicker-xo --json 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "locked"; then
  ok "read failure surfaced instead of reporting an empty inbox"
else
  bad "a failed read looked like 'no replies' (rc=$rc)"
fi

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
