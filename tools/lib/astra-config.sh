# astra-config.sh — personal, per-machine values that must never be committed
# (a phone number, the Tailnet name of another Mac). One file per machine:
#   ${XDG_CONFIG_HOME:-$HOME/.config}/astra/config
# with KEY="value" lines. Keys in use:
#   ASTRA_NOTIFY_PHONE    number botline and ollama-watch text (E.164)
#   ASTRA_NOTIFY_CHAT_ID  Messages chat id botline reads replies from
#   ASTRA_LMS_HOST        host running LM Studio (ambrosio, lms-prune)
#   ASTRA_PEER_HOST       the other Mac (ai-setup-diff)
#   ASTRA_LAUNCHD_PREFIX  reverse-DNS prefix for launchd labels astra creates (default com.astra)
#   ASTRA_WORKLOG         path to a worklog tool peer-review records into (optional)
#   ASTRA_PEER_REVIEW_REPOS  colon-separated repos peer-review also covers (optional)
#   GHOST_REPO            checkout whose tools/notes_html_append.sh handlebars notes-append runs
# Usage: . astra-config.sh; astra_config KEY   (prints the value, or nothing)
ASTRA_CONFIG_FILE="${ASTRA_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/astra/config}"
astra_config() {
  local v; eval "v=\${$1:-}"
  [ -n "$v" ] && { printf '%s\n' "$v"; return; }
  [ -f "$ASTRA_CONFIG_FILE" ] || return 0
  sed -n "s/^[[:space:]]*$1=//p" "$ASTRA_CONFIG_FILE" | tail -1 | sed -e 's/^"//' -e 's/"[[:space:]]*\(#.*\)\{0,1\}$//'
}
astra_config_required() {
  local v; v="$(astra_config "$1")"
  [ -n "$v" ] || { echo "astra: $1 is not set; add $1=\"...\" to $ASTRA_CONFIG_FILE" >&2; return 1; }
  printf '%s\n' "$v"
}

# The reverse-DNS prefix for launchd labels astra creates (com.astra.xcode-mcp-front, ...). A label
# names the person who owns the job, so it is configuration, never code: the default is neutral, and
# a machine that already runs jobs under another prefix sets ASTRA_LAUNCHD_PREFIX to keep them (a
# changed prefix would install a SECOND daemon beside the running one).
astra_launchd_prefix() {
  local p; p="$(astra_config ASTRA_LAUNCHD_PREFIX)"
  printf '%s\n' "${p:-com.astra}"
}
