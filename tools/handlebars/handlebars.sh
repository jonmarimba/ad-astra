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
export PATH="${ASTRA_PATH:-/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$PATH}"

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

# Support a command file for when args can't be passed through 'open' (Automator eats argv).
# Write the command + args to this file before launching the .app; the script reads it,
# runs the command, and deletes the file so the next bare launch does the default status check.
CMDFILE="${HANDLEBARS_CMDFILE:-$HOME/.handlebars_cmd}"
if [ -z "${1:-}" ] && [ -f "$CMDFILE" ]; then
  set -- $(cat "$CMDFILE")
  rm -f "$CMDFILE"
fi
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
  notes-icloud-test)
    # Diagnostic: check whether iCloud notes are visible from Handlebars' Aqua context.
    # AppleScript sees 0 iCloud notes from a terminal/tmux process; this tests whether the
    # .app bundle's proper pedigree makes a difference.
    osascript -e '
tell application "Notes"
  set out to ""
  repeat with a in accounts
    set out to out & (name of a) & ": " & (count of notes in a) & "\n"
  end repeat
  set defName to name of default account
  set defCount to count of notes in default account
  set out to out & "DEFAULT (" & defName & "): " & defCount
  return out
end tell' ;;
  notes-append)
    # Append HTML to an iCloud note by title. Delegates the actual AppleScript to
    # notes_html_append.sh but runs it FROM this .app's identity, so the Automation
    # (Notes) grant and Aqua pedigree apply.
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "handlebars notes-append: usage: handlebars.sh notes-append \"Note Title\" /path/to/content.html [match-index]" >&2
      exit 64
    fi
    # The checkout that holds tools/notes_html_append.sh: $GHOST_REPO, else GHOST_REPO in the
    # astra config file. No default path, because a default is only right on one machine.
    . "$(dirname "${BASH_SOURCE[0]}")/../lib/astra-config.sh"
    GHOST_REPO="$(astra_config_required GHOST_REPO)" || exit 64
    [ -f "$GHOST_REPO/tools/notes_html_append.sh" ] || { echo "handlebars notes-append: $GHOST_REPO/tools/notes_html_append.sh does not exist; fix GHOST_REPO" >&2; exit 66; }
    exec bash "$GHOST_REPO/tools/notes_html_append.sh" "$2" "$3" "${4:-}" ;;
  read-file)
    # Copy a TCC-protected file using Handlebars' FDA grant.
    # Reads source and dest paths from ~/.handlebars_read_file (one path per line)
    # to avoid CMDFILE word-splitting on paths with spaces (e.g. "All Mail.mbox").
    # Read-only — just copies the file. Useful for .emlx and other Mail-store files
    # that a non-FDA session cannot open. Dest must be outside the protected tree.
    READ_SPEC="${HOME}/.handlebars_read_file"
    if [ ! -f "$READ_SPEC" ]; then
      echo "handlebars read-file: write source and dest paths (one per line) to $READ_SPEC" >&2
      exit 64
    fi
    SRC="$(sed -n '1p' "$READ_SPEC")"
    DST="$(sed -n '2p' "$READ_SPEC")"
    rm -f "$READ_SPEC"
    if [ -z "$SRC" ] || [ -z "$DST" ]; then
      echo "handlebars read-file: spec file must have source on line 1, dest on line 2" >&2
      exit 64
    fi
    if [ ! -f "$SRC" ]; then
      echo "handlebars read-file: file not found: $SRC" >&2
      exit 1
    fi
    cp "$SRC" "$DST"
    echo "handlebars read-file: copied $(basename "$SRC") -> $DST" ;;
  notes-db-count)
    # Read NoteStore.sqlite directly (needs FDA) and report how many notes
    # actually exist in the database vs what AppleScript can see.
    python3 -c "
import sqlite3, tempfile, os, shutil
store = os.path.expanduser('~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite')
td = tempfile.mkdtemp()
dest = os.path.join(td, 'NoteStore.sqlite')
src = sqlite3.connect(f'file:{store}?mode=ro', uri=True)
dst = sqlite3.connect(dest)
src.backup(dst)
src.close(); dst.close()
con = sqlite3.connect(dest)
total = con.execute('SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT WHERE ZTITLE1 IS NOT NULL').fetchone()[0]
not_del = con.execute('SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT WHERE ZTITLE1 IS NOT NULL AND (ZMARKEDFORDELETION IS NULL OR ZMARKEDFORDELETION != 1)').fetchone()[0]
print(f'NoteStore rows with titles: {total} (not-deleted: {not_del})')
for row in con.execute('''
    SELECT a.ZNAME,
           (SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT n
            WHERE n.ZACCOUNT4 = a.Z_PK AND n.ZTITLE1 IS NOT NULL
            AND (n.ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION != 1)) as cnt
    FROM ZICCLOUDSYNCINGOBJECT a
    WHERE a.ZNAME IS NOT NULL AND a.ZTYPEUTI IS NULL
    AND EXISTS (SELECT 1 FROM ZICCLOUDSYNCINGOBJECT n WHERE n.ZACCOUNT4 = a.Z_PK)
    ORDER BY cnt DESC
'''):
    print(f'  {row[0]}: {row[1]}')
con.close(); shutil.rmtree(td, ignore_errors=True)
" ;;
  *) echo "handlebars: unknown domain '$DOMAIN'" >&2; exit 64 ;;
esac

echo "handlebars: run complete."
