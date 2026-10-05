#!/bin/bash
# Detached waiter armed by arm.sh. Speaks only if its marker still exists and
# still holds its nonce, and (by default) only while the display is awake:
# Jonathan often remote-controls with the screen asleep and wants silence then.
# Apple Silicon has no IODisplayWrangler; powerd's "display is on" assertion is
# the signal, and if it cannot be confirmed the nag stays quiet.
sleep "${IDLE_NAG_DELAY:-25}"
[ -f "$IDLE_MARKER" ] && [ "$(cat "$IDLE_MARKER" 2>/dev/null)" = "$IDLE_NONCE" ] || exit 0
if [ "${IDLE_NAG_REQUIRE_DISPLAY:-1}" = 1 ]; then
  pmset -g assertions 2>/dev/null | grep -qi 'display is on' || exit 0
fi
# Aman (English, India) is Jonathan's preferred voice; on a Mac without it,
# fall back to the system voice rather than staying silent.
phrase="${IDLE_NAG_PHRASE:-Dude. Look over here.}"
"${IDLE_NAG_SAY:-say}" -v "${IDLE_NAG_VOICE:-Aman}" "$phrase" 2>/dev/null || "${IDLE_NAG_SAY:-say}" "$phrase"
rm -f "$IDLE_MARKER"
