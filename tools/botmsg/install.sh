#!/usr/bin/env bash
# botmsg — install into a repo so any bot working there can text a human.
#
#   ./install.sh                  dependencies only
#   ./install.sh --into <repo>    dependencies + place botmsg in <repo>/.astra/
#
# After installing, tell it where to write. Either set BOTMSG_TO, or create
# <repo>/.astra/botmsg.json:
#
#     {"to": "+15555550100"}
#
# Nothing here hardcodes a phone number or a bot identity. A different human,
# number or bot needs configuration, not an edit.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

install_deps() {
  if command -v brew >/dev/null; then
    brew bundle --file="$HERE/Brewfile"
  else
    echo "no brew — install imsg yourself: https://github.com/openclaw/imsg" >&2
  fi
  command -v imsg >/dev/null || { echo "imsg is not on PATH after install" >&2; exit 69; }
  imsg --help >/dev/null 2>&1 || { echo "imsg present but not runnable" >&2; exit 69; }
}

case " $* " in
  *" --into "*) ;;
  *) install_deps; echo "botmsg deps ready. Wire a repo: $0 --into <repo>"; exit 0 ;;
esac

. "$HERE/../lib/astra-install.sh"
astra_target "$@"
install_deps
astra_place botmsg botmsg
chmod +x "$TARGET/.astra/botmsg/botmsg"

echo
echo "Set a destination before first use:"
echo "    echo '{\"to\": \"+1XXXXXXXXXX\"}' > $TARGET/.astra/botmsg.json"
echo "Then:"
echo "    $TARGET/.astra/botmsg/botmsg send  --as my-bot --text 'hello'"
echo "    $TARGET/.astra/botmsg/botmsg inbox --as my-bot"
