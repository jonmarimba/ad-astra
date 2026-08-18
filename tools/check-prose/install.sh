#!/usr/bin/env bash
# check-prose — install the prose checker into a given repo.
#
# Installs check-prose.js AND rules.json together. The rules are DATA and travel
# with the tool, which is the whole point: the previous version had its word list
# hardcoded in one repo's JS, drifting from the skill and from Jonathan's own
# CLAUDE.md.
#
# A repo may extend without forking by adding .check-prose.json at its root.
#
# Lands in <repo>/.astra/check-prose/ — see tools/lib/astra-install.sh for why
# that location, and why the repo pulls updates rather than astra pushing them.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"

astra_target "$@"
astra_place check-prose check-prose.js rules.json
