#!/bin/bash
# handlebars.sh — the REPROGRAMMABLE payload for Handlebars.app.
#
# ============================================================================================
# GUARDRAILS — DO NOT DELETE, DO NOT LOOSEN WITHOUT A REAL CONVERSATION WITH JONATHAN FIRST.
# (Jonathan, 2026-08-14, while this tool was being built: "we think about the security
# implications and the guardrails as we go. And put those guardrails at the top of the shell
# script with a do not delete directive." Also: "you will have the strings that control the
# system... and you can do anything that you want sooo..." — that trailing ellipsis is the
# actual question this block answers, in writing, so it survives every future session that
# edits this file. Whatever session is reading this: you are the "sooo" being answered.)
#
# This script is the reprogrammable half of a standing, broadly-granted macOS identity
# (Handlebars.app). Editing it can change what a code-signed process can silently do to
# Jonathan's machine and data, across EVERY TCC domain it has been granted — without a new
# permission prompt, without him necessarily watching this specific run. That is exactly the
# capability the Flobots song this tool is named for is ABOUT, and the guardrails exist
# because the song's answer to "I can do anything I want, so..." only stays good if someone
# keeps choosing it on purpose, every time, not on the first easy occasion to skip it.
#
# The rules, unconditionally:
#   1. GRANTS ARE ADDED ONE AT A TIME, IN THE SEAT, WITH JONATHAN WATCHING. Never propose or
#      script a batch grant-everything flow. Never ask him to grant a pane "for later, just in
#      case." Each domain gets added only when a real, named task needs it right now.
#   2. NOTHING DESTRUCTIVE OR IRREVERSIBLE RUNS UNATTENDED. Sending messages, deleting data,
#      spending money, modifying other apps' data, posting/publishing anything — same explicit-
#      permission-in-chat rule that governs every other tool here (see the outer system
#      prompt's action categories). Holding FDA/Automation/etc. does not waive that; if
#      anything it raises the bar, because there's no OS-level prompt left to catch a mistake.
#   3. LOG EVERY REAL CAPABILITY CHANGE. An edit to this file that adds or changes what it DOES
#      (not the proof-of-reach checks) gets a git commit message that says so in plain words —
#      no vague "update handlebars.sh". The log at handlebars.log is where a RUN is audited;
#      git history is where a CAPABILITY CHANGE is audited. Both matter.
#   4. NO COVERT USE. Nothing this script does should be a surprise to Jonathan if he read this
#      file. If a task would need to be hidden from him to work, that is the signal to stop and
#      ask, not to proceed quietly because the tower makes it technically possible.
#   5. THIS BLOCK IS NOT A FORMALITY. If a future session (any model, any brand) is tempted to
#      delete, shrink, or route around this comment because it's "just documentation" — that
#      impulse is precisely the failure mode the block exists to catch. Leave it, follow it,
#      and if it's ever genuinely wrong, say so to Jonathan and let HIM edit it.
# ============================================================================================
#
# "I can ride my bike with no handlebars" — grant the .app bundle the TCC permissions it needs,
# ONE AT A TIME per the discipline above, and this file is the only thing that ever has to
# change to reprogram what the granted identity DOES. Per wrap-in-app's design, this script
# lives OUTSIDE the .app bundle — editing it freely never touches the app's hash, so the grants
# survive every rewrite. That's the whole point: mint the tower once, reprogram it forever —
# and the guardrails above are what keep "reprogram it forever" from meaning "skeleton key."
#
# THIS FILE SHIPS AS A TEMPLATE. It does nothing destructive by default — it just proves the
# tower is standing (logs which TCC-gated things it can actually reach) until you replace the
# body below with a real task. Treat every edit here as a genuine capability change: log it,
# and remember the .app can now do WHATEVER this script says, with EVERY grant it holds.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

echo "handlebars: tower run @ $(date '+%Y-%m-%d %H:%M:%S')"

# ---- ONE grant at a time, driven interactively, never a batch-grant-everything run ----
# Jonathan (2026-08-14): "we do one at a time in the script. And coordinate where I grant
# access in the seat with your direction." NOT "grant every TCC pane up front" — that's a
# skeleton key. This is a deliberate, sequential build: pick ONE domain below, run this
# script, GhOST tells Jonathan which System Settings pane to open and add Handlebars.app to,
# he does it while watching, THEN this check proves that ONE grant took. Never batch.
#
# Usage: handlebars.sh <domain>   where <domain> is one of: fda | automation | screen |
#                                  messages | photos | mic | accessibility | camera | contacts | calendar
# No argument = list domains and their current OK/BLOCKED state (read-only, checks only
# what's ALREADY been granted so far — does not prompt for anything new).

check(){ # usage: check <label> <cmd...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  OK      $label"; return 0
  else echo "  BLOCKED $label (rc=$?)"; return 1
  fi
}

DOMAIN="${1:-}"
case "$DOMAIN" in
  fda)           check "Full Disk Access (~/Library/Mail readable)" test -r "$HOME/Library/Mail" ;;
  automation)    check "Automation -> Notes (osascript)" osascript -e 'tell application "Notes" to count of notes' ;;
  screen)        check "Screen Recording (screencapture)" screencapture -x -t jpg /tmp/handlebars_screencheck.jpg
                 rm -f /tmp/handlebars_screencheck.jpg ;;
  messages)      check "Messages DB (chat.db readable)" test -r "$HOME/Library/Messages/chat.db" ;;
  photos)        check "Photos library readable" test -r "$HOME/Pictures/Photos Library.photoslibrary" ;;
  contacts)     check "Contacts (read one vCard)" osascript -e 'tell application "Contacts" to get name of first person' ;;
  calendar)     check "Calendar (count calendars)" osascript -e 'tell application "Calendar" to count of calendars' ;;
  mic)          # ffmpeg records 0.1s from the default audio input — TCC-gated, no audible side-effect
                check "Microphone (ffmpeg 0.1s)" ffmpeg -f avfoundation -i ":0" -t 0.1 -y /tmp/handlebars_miccheck.wav -loglevel quiet
                rm -f /tmp/handlebars_miccheck.wav ;;
  camera)       # ffmpeg grabs a single frame from the default camera — TCC-gated, fast, no GUI
                check "Camera (ffmpeg single frame)" ffmpeg -f avfoundation -framerate 1 -i "0" -frames:v 1 -y /tmp/handlebars_camcheck.jpg -loglevel quiet
                rm -f /tmp/handlebars_camcheck.jpg ;;
  accessibility) check "Accessibility (AX: Finder)" osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' ;;
  "")
    echo "handlebars: current grant state (checks only; does not request anything new)"
    check "Full Disk Access"        test -r "$HOME/Library/Mail"
    check "Automation -> Notes"     osascript -e 'tell application "Notes" to count of notes'
    check "Screen Recording"        screencapture -x -t jpg /tmp/handlebars_screencheck.jpg; rm -f /tmp/handlebars_screencheck.jpg
    check "Messages DB"             test -r "$HOME/Library/Messages/chat.db"
    check "Photos library"          test -r "$HOME/Pictures/Photos Library.photoslibrary"
    check "Contacts"               osascript -e 'tell application "Contacts" to get name of first person'
    check "Calendar"               osascript -e 'tell application "Calendar" to count of calendars'
    check "Microphone"             ffmpeg -f avfoundation -i ":0" -t 0.1 -y /tmp/handlebars_miccheck.wav -loglevel quiet; rm -f /tmp/handlebars_miccheck.wav
    check "Camera"                 ffmpeg -f avfoundation -framerate 1 -i "0" -frames:v 1 -y /tmp/handlebars_camcheck.jpg -loglevel quiet; rm -f /tmp/handlebars_camcheck.jpg
    check "Accessibility (AX)"     osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
    ;;
  *) echo "handlebars: unknown domain '$DOMAIN'" >&2; exit 64 ;;
esac

echo "handlebars: run complete."
