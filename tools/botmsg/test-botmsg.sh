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
trap 'cd /; rm -rf "$WORK"' EXIT

# RUN FROM A NEUTRAL DIRECTORY. botmsg discovers its destination from
# ./.astra/botmsg.json, so the suite's results depended on where it was
# launched from: green inside astra, which has no .astra/, and red inside any
# repo that had actually installed botmsg — test 8 asserts that a missing
# destination is refused, and a configured consumer workspace supplies one.
# OpenClaw hit this running the suite from its own workspace before adopting,
# and it is a real portability bug rather than a cosmetic one: a test whose
# outcome depends on the caller's working directory is testing the caller.
cd "$WORK"
export BOTMSG_STATE="$WORK/state"
export BOTMSG_TO="+15555550100"
export BOTMSG_IMSG_BIN="$WORK/fake-imsg"

# Fake imsg. Reads a transcript fixture and mimics the real tool's contract:
# newest-first JSON lines, is_from_me for outbound, reply_to_text when the human
# used the native reply gesture.
make_fake() {
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
}
make_fake
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

echo "== 1. A reply whose context names a bot routes to that bot =="
out="$("$BOTMSG" inbox --as ghost-claude --json)"
if echo "$out" | grep -q "nice, ship it" && echo "$out" | grep -q "reply-context"; then
  ok "reply-context claimed by the named bot"
else
  bad "reply-context not routed (got: $(echo "$out" | tr -d '\n' | head -c 160))"
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
# cwd is $WORK, which has no .astra/ — asserted below rather than assumed,
# because the whole point of this test is that nothing supplies a destination.
[ -e "$PWD/.astra/botmsg.json" ] && bad "test isolation broken: a config exists in $PWD"
out="$(env -u BOTMSG_TO "$BOTMSG" send --as x --text hi 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "no destination"; then
  ok "refused without a destination"
else
  bad "sent, or failed unclearly, with no destination configured (rc=$rc)"
fi

# The other half: discovery must actually WORK. Isolating cwd would otherwise
# be indistinguishable from breaking config lookup entirely.
mkdir -p "$WORK/cfgtest/.astra"
echo '{"to": "+15555550199"}' > "$WORK/cfgtest/.astra/botmsg.json"
out="$(cd "$WORK/cfgtest" && env -u BOTMSG_TO "$BOTMSG" whoami --as x 2>&1)"
if echo "$out" | grep -q "5555550199"; then
  ok "a repo-local .astra/botmsg.json IS discovered when present"
else
  bad "config discovery is broken, not merely isolated: $out"
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
# RESTORE the working fake. Leaving the broken one in place made every later
# test run against a dead transport and fail for a reason that had nothing to
# do with what it was testing — four false failures, all pointing at the wrong
# code. A test that damages shared fixtures for the tests after it is its own
# kind of tautology.
make_fake

echo "== 11. A reply must go to who spoke last BEFORE it, not last overall =="
# OpenClaw's blocking review finding, 2026-08-18. Computing last_sender once
# over the whole transcript let a bot claim a reply that was answering someone
# else's earlier question, purely because it happened to speak afterwards.
# Stealing a reply is the exact failure this tool exists to prevent.
cat > "$FIXTURE" <<'JSON'
[
 {"id": 20, "is_from_me": true,  "text": "[ghost-openclaw] should I ship it?"},
 {"id": 21, "is_from_me": false, "text": "yes"},
 {"id": 22, "is_from_me": true,  "text": "[ghost-claude] unrelated status update"}
]
JSON
rm -rf "$BOTMSG_STATE"
out="$("$BOTMSG" inbox --as ghost-claude --json)"
if echo "$out" | grep -q '"yes"'; then
  bad "ghost-claude stole a reply meant for ghost-openclaw — spoke later, claimed earlier"
else
  ok "later speaker did not claim the earlier reply"
fi
rm -rf "$BOTMSG_STATE"
out="$("$BOTMSG" inbox --as ghost-openclaw --json)"
if echo "$out" | grep -q '"yes"'; then
  ok "the bot that actually asked received the answer"
else
  bad "the answer reached nobody — worse than misrouting (got: $(echo "$out" | tr -d '\n'))"
fi

echo "== 12. reply_to_text is a GUESS, never reported as exact =="
# It reads as certainty and is not. On Jonathan's Google Voice SMS thread,
# Messages auto-associates each inbound with the preceding message — measured:
# ten of ten inbound carried reply_to_text, two pointing at his OWN texts. So
# it carries no more information than recency and must not outrank an explicit
# address or claim higher confidence.
cat > "$FIXTURE" <<'JSON'
[
 {"id": 30, "is_from_me": true,  "text": "[ghost-claude] here is a thing"},
 {"id": 31, "is_from_me": false, "text": "ok do it",
  "reply_to_text": "[ghost-claude] here is a thing"}
]
JSON
rm -rf "$BOTMSG_STATE"
out="$("$BOTMSG" inbox --as ghost-claude --json)"
if echo "$out" | grep -q "guess"; then
  ok "reply-context claimed but labelled a guess"
else
  bad "reported reply_to_text as certainty: $(echo "$out" | tr -d '\n' | head -c 140)"
fi

echo "== 13. An explicit tag still beats everything =="
cat > "$FIXTURE" <<'JSON'
[
 {"id": 40, "is_from_me": true,  "text": "[ghost-claude] mine"},
 {"id": 41, "is_from_me": false, "text": "[ghost-openclaw] this one is yours",
  "reply_to_text": "[ghost-claude] mine"}
]
JSON
rm -rf "$BOTMSG_STATE"
out="$("$BOTMSG" inbox --as ghost-claude --json)"
if echo "$out" | grep -q "this one is yours"; then
  bad "reply-context overrode an explicit address to another bot"
else
  ok "explicit address beat both reply-context and recency"
fi

echo "== 14. A watermark behind the visible window must FAIL, not skip silently =="
# Also OpenClaw's. Messages between the watermark and the window are invisible;
# skipping them quietly means a real instruction is dropped while the tool
# reports an empty inbox.
cat > "$FIXTURE" <<'JSON'
[
 {"id": 900, "is_from_me": true,  "text": "[ghost-claude] recent"},
 {"id": 901, "is_from_me": false, "text": "answer"}
]
JSON
rm -rf "$BOTMSG_STATE"; mkdir -p "$BOTMSG_STATE"
echo '{"last_seen_id": 5}' > "$BOTMSG_STATE/ghost-claude.json"
out="$("$BOTMSG" inbox --as ghost-claude --json 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "gap"; then
  ok "gap between watermark and window refused loudly"
else
  bad "silently skipped an invisible range (rc=$rc)"
fi


echo "== 15. The READ-SIDE gate: should this bot answer at all? =="
# The hole Jonathan found by demonstration. botmsg governed sending and
# governed reading for anything that read through inbox — and nothing did, so
# one message got two answers. "Except openclaw responded." A routing tool only
# the sender consults is decoration; the check has to sit at the read side.
cat > "$FIXTURE" <<'JSON'
[
 {"id": 50, "is_from_me": true, "text": "[ghost-claude] I spoke last"}
]
JSON
"$BOTMSG" claims --as ghost-claude --text "[ghost-claude] do the thing" >/dev/null 2>&1
[ $? -eq 0 ] && ok "explicit tag for me: answer it" || bad "refused a message addressed to me"

"$BOTMSG" claims --as ghost-claude --text "[ghost-openclaw] do the thing" >/dev/null 2>&1
[ $? -eq 3 ] && ok "explicit tag for another bot: stay quiet (exit 3)" || bad "did not stand down for a message addressed elsewhere"

"$BOTMSG" claims --as ghost-claude --text "sure, go ahead" >/dev/null 2>&1
[ $? -eq 0 ] && ok "bare message, I spoke last: answer it" || bad "refused a bare message when I was the last speaker"

"$BOTMSG" claims --as ghost-openclaw --text "sure, go ahead" >/dev/null 2>&1
[ $? -eq 4 ] && ok "bare message, someone else spoke last: stay quiet (exit 4)" || bad "would have answered a bare message aimed at another bot"

echo "== 16. The gate must not mutate state =="
# A question about one message. If asking changed the watermark, a bot that
# checks before answering would lose the next message, or get a different
# answer on a second check.
rm -rf "$BOTMSG_STATE"
"$BOTMSG" claims --as ghost-claude --text "sure" >/dev/null 2>&1
if [ -e "$BOTMSG_STATE/ghost-claude.json" ]; then
  bad "the gate wrote state — asking twice could give two different answers"
else
  ok "asking did not mutate state"
fi


echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
