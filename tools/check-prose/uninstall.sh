#!/usr/bin/env bash
# check-prose — remove the prose checker from a given repo.
#
# The previous version of this file could not remove anything. It was cloned
# from install.sh and gated on `if [ "uninstall" = "install" ]`, a comparison of
# two literals that is always false, so the removal branch was the only one that
# could ever run in uninstall.sh and the copy branch was the only one that could
# ever run in install.sh. Both worked by accident of the string that was
# substituted, and neither said so. Written out properly here.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"

astra_target "$@"
astra_remove check-prose
