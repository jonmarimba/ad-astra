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

# Each domain probe is:
#   1. Innocuous — reads one datum, captures one frame, records 0.1s of silence, then cleans up.
#   2. TCC-triggering — the specific syscall/IPC that makes macOS register a pairing in
#      System Settings → Privacy & Security → <pane>, so the user can grant it.
#   3. Self-cleaning — temp files go through mktemp and are removed in a trap.
#   4. Portable — uses only macOS system tools (osascript, screencapture). The mic and camera
#      probes need ffmpeg (brew install ffmpeg); if it's missing they report SKIP, not FAIL.
#
# "Prompt-able" vs "add-in-Settings": Automation/Mic/Camera/Accessibility will pop a macOS
# consent dialog on first attempt. FDA/Screen Recording/Messages/Photos/Contacts/Calendar
# do NOT prompt — the user must add the app manually in System Settings. The output tells
# the user which pane to visit for each BLOCKED domain.

TMPDIR_HB="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_HB"' EXIT

# check <short_label> <settings_pane_name> <cmd...>
#   Runs the command silently. Reports OK / BLOCKED / SKIP (missing tool).
#   On BLOCKED, prints which System Settings pane to visit.
check(){
  local label="$1" pane="$2"; shift 2
  local cmd_name="$1"
  if ! command -v "$cmd_name" >/dev/null 2>&1; then
    echo "  SKIP    $label  (${cmd_name} not installed)"
    return 0
  fi
  local err_file="$TMPDIR_HB/${label// /_}.err"
  if "$@" >"$TMPDIR_HB/out" 2>"$err_file"; then
    echo "  OK      $label"
    return 0
  else
    local rc=$?
    echo "  BLOCKED $label  ->  System Settings > Privacy & Security > $pane"
    # Show first line of stderr if it's informative (not empty, not just usage noise)
    local first_err
    first_err="$(head -1 "$err_file" 2>/dev/null)"
    if [ -n "$first_err" ]; then
      echo "          ($first_err)"
    fi
    return $rc
  fi
}

DOMAIN="${1:-}"
case "$DOMAIN" in
  fda)
    check "Full Disk Access" "Full Disk Access" \
      test -r "$HOME/Library/Mail" ;;
  automation)
    check "Automation (Notes)" "Automation > Handlebars > Notes" \
      osascript -e 'tell application "Notes" to count of notes' ;;
  screen)
    check "Screen Recording" "Screen Recording & System Audio" \
      screencapture -x -t jpg "$TMPDIR_HB/screen.jpg" ;;
  messages)
    check "Messages" "Full Disk Access" \
      test -r "$HOME/Library/Messages/chat.db" ;;
  photos)
    check "Photos" "Photos" \
      test -r "$HOME/Pictures/Photos Library.photoslibrary" ;;
  contacts)
    check "Contacts" "Contacts" \
      osascript -e 'tell application "Contacts" to get name of first person' ;;
  calendar)
    check "Calendar" "Calendars" \
      osascript -e 'tell application "Calendar" to count of calendars' ;;
  mic)
    check "Microphone" "Microphone" \
      ffmpeg -f avfoundation -i ":0" -t 0.1 -y "$TMPDIR_HB/mic.wav" -loglevel quiet ;;
  camera)
    check "Camera" "Camera" \
      ffmpeg -f avfoundation -framerate 1 -i "0" -frames:v 1 -y "$TMPDIR_HB/cam.jpg" -loglevel quiet ;;
  accessibility)
    check "Accessibility" "Accessibility" \
      osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' ;;
  "")
    echo "handlebars: current grant state  (8 TCC domains)"
    echo "  Each BLOCKED line shows the System Settings pane where you add Handlebars.app."
    echo "  Mic and Camera probes need ffmpeg (brew install ffmpeg); SKIP = not installed."
    echo ""
    check "Full Disk Access"    "Full Disk Access" \
      test -r "$HOME/Library/Mail"
    check "Screen Recording"    "Screen Recording & System Audio" \
      screencapture -x -t jpg "$TMPDIR_HB/screen.jpg"
    check "Automation (Notes)"  "Automation > Handlebars > Notes" \
      osascript -e 'tell application "Notes" to count of notes'
    check "Contacts"            "Contacts" \
      osascript -e 'tell application "Contacts" to get name of first person'
    check "Calendar"            "Calendars" \
      osascript -e 'tell application "Calendar" to count of calendars'
    check "Accessibility"       "Accessibility" \
      osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
    check "Microphone"          "Microphone" \
      ffmpeg -f avfoundation -i ":0" -t 0.1 -y "$TMPDIR_HB/mic.wav" -loglevel quiet
    check "Camera"              "Camera" \
      ffmpeg -f avfoundation -framerate 1 -i "0" -frames:v 1 -y "$TMPDIR_HB/cam.jpg" -loglevel quiet
    ;;
  *) echo "handlebars: unknown domain '$DOMAIN'" >&2; exit 64 ;;
esac

echo "handlebars: run complete."
