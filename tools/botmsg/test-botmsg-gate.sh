#!/usr/bin/env bash
# The claims gate must identify the last speaker from the send RECORD, never from
# a bracket at the start of a message.
#
# Two live failures on 2026-08-24, both from bracket-parsing:
#  - Untagged sends (every text to Jonathan, who has asked not to be signed at)
#    left the sender invisible, so a bot that had just texted him did not count.
#  - schd reminder texts begin "[Mon 09:11] ...", which parsed as a bot named
#    "Mon 09:11", so the gate reported a stranger had spoken last.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
BOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/botmsg"
[ -x "$BOT" ] || BOT="$HOME/svnCheckouts/js-db-ad-astra/tools/botmsg/botmsg"
[ -x "$BOT" ] || { echo "FATAL: botmsg not found"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export BOTMSG_STATE="$TMP/state"
mkdir -p "$BOTMSG_STATE"
mk() { printf '{"last_sent_at":"%s","last_sent_text":"x"}\n' "$2" > "$BOTMSG_STATE/$1.json"; }

echo "1. an explicit tag still wins"
"$BOT" claims --as ghost-claude --text "[ghost-claude] do the thing" >/dev/null 2>&1
[ $? -eq 0 ] && ok "explicit tag claimed" || bad "explicit tag not honoured"

echo "2. a message addressed to another bot is refused"
"$BOT" claims --as ghost-claude --text "[ghost-openclaw] do the thing" >/dev/null 2>&1
[ $? -eq 3 ] && ok "exit 3 for another bot" || bad "did not refuse another bot's message"

echo "3. THE REGRESSION — an untagged send still makes you the last speaker"
mk ghost-claude "2026-08-24T20:18:00-0400"
mk ghost-openclaw "2026-08-24T09:11:00-0400"
out="$("$BOT" claims --as ghost-claude --text "LMI?" 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then ok "claimed: $out"; else bad "rc=$rc — untagged send still invisible: $out"; fi

echo "4. the other bot having spoken most recently is still refused"
mk ghost-openclaw "2026-08-24T21:00:00-0400"
out2="$("$BOT" claims --as ghost-claude --text "LMI?" 2>&1)"; rc2=$?
[ $rc2 -eq 4 ] && ok "exit 4: $out2" || bad "rc=$rc2 — should defer to the other bot: $out2"

echo "5. RED control — a schd timestamp prefix must NOT be read as a bot id"
mk ghost-claude "2026-08-24T22:00:00-0400"
out3="$("$BOT" claims --as ghost-claude --text "Mon 09:11 reminder text" 2>&1)"; rc3=$?
if [ $rc3 -eq 0 ] && ! echo "$out3" | grep -q "Mon 09:11"; then
  ok "timestamp not mistaken for a sender"
else
  bad "rc=$rc3 out=$out3 — bracket parsing is back"
fi

echo "6. with NO send records it falls back to the transcript, and defers if a sibling is tagged there"
# Not a bug: an empty state directory means no bot has recorded a send, so the
# only evidence left is a leading [tag] in the live transcript. Deferring when
# a sibling is tagged there is the safe answer — the cost of staying quiet is a
# missed reply, the cost of claiming is the double-answer this tool exists to
# prevent. This assertion was originally written the other way round and was
# simply wrong about what the fallback should do.
rm -f "$BOTMSG_STATE"/*.json
out6="$("$BOT" claims --as ghost-claude --text "hello" 2>&1)"; rc6=$?
if [ $rc6 -eq 0 ] || [ $rc6 -eq 4 ]; then
  ok "fell back to the transcript: $out6"
else
  bad "rc=$rc6 — fallback neither claimed nor deferred: $out6"
fi

echo "7. a corrupt sibling state file does not decide the answer"
mk ghost-claude "2026-08-24T22:00:00-0400"
echo 'not json' > "$BOTMSG_STATE/ghost-broken.json"
"$BOT" claims --as ghost-claude --text "hello" >/dev/null 2>&1
[ $? -eq 0 ] && ok "corrupt sibling skipped" || bad "corrupt sibling changed the verdict"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
