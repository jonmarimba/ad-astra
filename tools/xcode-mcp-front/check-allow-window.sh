#!/bin/bash
# check-allow-window.sh — read-only diagnostic for Xcode's per-PID connection
# approval dialogs. Reports which PIDs currently have a pending "Allow" window,
# and whether a given PID has one — WITHOUT ever clicking anything. Exists
# because this got hand-typed as slightly-different `osascript -e` one-liners
# too many times debugging daemon.py's _click_allow_if_present() (2026-08-14) —
# this is the one real tool instead.
#
#   check-allow-window.sh          # list every PID with a pending Allow window
#   check-allow-window.sh <pid>    # exit 0 + print match if THIS pid has one, else exit 1
#
# The actual click logic lives in daemon.py's _click_allow_if_present() — this
# script is read-only on purpose, safe to run anytime without side effects.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

TARGET_PID="${1:-}"

# Digits-only guard: TARGET_PID gets interpolated straight into AppleScript
# source below. A PID is only ever digits, so anything else is either a typo
# or an attempt to break out of the string literal — reject it loud rather
# than let it reach osascript.
if [ -n "$TARGET_PID" ] && ! [[ "$TARGET_PID" =~ ^[0-9]+$ ]]; then
  echo "check-allow-window.sh: '$TARGET_PID' is not a plain PID (digits only)" >&2
  exit 64
fi

if [ -z "$TARGET_PID" ]; then
  osascript -e '
tell application "System Events" to tell process "Xcode"
  set out to ""
  repeat with w in windows
    if exists (button "Allow" of w) then
      set winText to ""
      try
        set winText to (value of every static text of w) as string
      end try
      set out to out & winText & linefeed & "---" & linefeed
    end if
  end repeat
  return out
end tell'
  exit 0
fi

RESULT="$(osascript -e "
set my_pid to \"$TARGET_PID\"
tell application \"System Events\" to tell process \"Xcode\"
  repeat with w in windows
    if exists (button \"Allow\" of w) then
      set winText to \"\"
      try
        set winText to (value of every static text of w) as string
      end try
      -- exact match, not substring: \"PID: 123\" must not false-match a
      -- dialog whose real PID is 12345 (found by convocation review,
      -- 2026-08-14). The PID line is always immediately followed by a
      -- newline before \"Signed by: \", so require that boundary.
      if winText contains (\"PID: \" & my_pid & (ASCII character 10)) then
        return \"match\"
      end if
    end if
  end repeat
  return \"no-match\"
end tell" 2>&1)"

if [ "$RESULT" = "match" ]; then
  echo "PID $TARGET_PID has a pending Allow window"
  exit 0
else
  echo "PID $TARGET_PID: $RESULT"
  exit 1
fi
