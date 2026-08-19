#!/usr/bin/env bash
# botmsg — remove from a repo.
#
# Leaves ~/.botmsg state alone. Those files hold per-bot watermarks, and
# deleting them makes the next install replay every old message as new, which
# for a messaging tool means re-acting on instructions the human already gave.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/astra-install.sh"
astra_target "$@"
astra_remove botmsg
echo "note: per-bot watermarks in ~/.botmsg were left in place deliberately."
