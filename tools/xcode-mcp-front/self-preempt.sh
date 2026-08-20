# self-preempt.sh — sourced (not run) by each instance's *-run.sh, right before
# it execs daemon.py. Shared so the two instances don't duplicate this logic AND
# don't accidentally kill each other.
#
# Confirmed live, 2026-08-14: `launchctl kickstart -k` only reliably signals the
# top-level tracked PID (the Automator stub); the embedded script's own
# descendant tree (zsh -> uv -> python) doesn't always get cleanly
# cascade-killed with it, so a "restart" can leave the OLD daemon.py alive and
# still bound to the port while a brand new one starts up next to it and fails
# on EADDRINUSE. Only one instance should ever hold a given port, so killing
# any other daemon.py already bound to THIS instance's port is correct
# self-healing, not a hack.
#
# Port-scoped, not blanket: both instances run the exact same daemon.py path,
# so a blind `pgrep -f daemon.py` kill would also kill the OTHER instance —
# only touch a pid that's actually bound to our own port.
#
# Requires PORT to be set by the caller before sourcing this.
#
# -nP on lsof is load-bearing, not decoration: without it, lsof substitutes
# /etc/services names for well-known ports. Port 8765 is registered there as
# "ultraseek-http" (confirmed live, 2026-08-14 - the running daemon's lsof line
# reads "TCP localhost:ultraseek-http (LISTEN)"), so a bare `grep ":8765 "`
# never matches and this whole self-preempt step silently no-ops for that
# port - exactly the stale-daemon-holds-the-port disease this script exists to
# cure. Port 8767 happened to work by luck (no /etc/services entry for it).
for _pid in $(pgrep -f "$HERE/daemon.py" 2>/dev/null); do
  if lsof -nP -p "$_pid" 2>/dev/null | grep -q ":$PORT "; then
    echo "self-preempt: killing stale daemon.py (pid $_pid) on port $PORT before starting fresh"
    kill -9 "$_pid" 2>/dev/null
  fi
done
unset _pid
sleep 1  # let the port actually free up before we try to bind it
