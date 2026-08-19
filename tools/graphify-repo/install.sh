#!/usr/bin/env bash
# install.sh — graphify-repo: dependencies, and optionally wire it into a repo.
#
#   ./install.sh                  dependencies only (uv + the graphify CLI)
#   ./install.sh --into <repo>    dependencies + place the runner in <repo>/.astra/
#
# Jonathan asked for this in the "Graphify + obsidian" note: "I'd like to get
# graphify and this into a Maharam branch to trial. I probably need to have
# exportable hooks for this. Let's make those and put them in @astra for now —
# Andrew and I both have access to that."
#
# The per-repo half is built here. The HOOK half is deliberately not, and the
# reason is in the README: a commit hook has to know how often the thing should
# run, and graphify re-walks the tree with tree-sitter, so on a large repo that
# is not a cost to guess at on someone else's behalf. Wiring a trigger before
# knowing the cadence is how a tool becomes the thing everyone disables.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

install_deps() {
  command -v brew >/dev/null && brew bundle --file="$HERE/Brewfile" || echo "no brew; ensure uv present"
  command -v graphify >/dev/null || uv tool install graphifyy
  graphify --help >/dev/null 2>&1 \
    && echo "graphify-repo ready. Usage: $HERE/graphify-repo <repo-path> [--label-backend ollama --label-model <m>]"
}

case " $* " in
  *" --into "*) ;;
  *) install_deps; exit 0 ;;
esac

. "$HERE/../lib/astra-install.sh"
astra_target "$@"
install_deps
astra_place graphify-repo graphify-repo
chmod +x "$TARGET/.astra/graphify-repo/graphify-repo"

cat <<EOF

Wired into $TARGET/.astra/graphify-repo/

Run it on demand:
    "$TARGET/.astra/graphify-repo/graphify-repo" "$TARGET"

Output lands in graphify-out/, which the runner adds to .git/info/exclude — the
repo's own .gitignore is never touched, which is what makes this safe to trial
in a client repo. The report surfaces in Obsidian under graphify/<repo>/.

No commit hook is installed. Decide the cadence first — see the README.
EOF
