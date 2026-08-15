#!/usr/bin/env bash
# uninstall.sh — remove Handlebars.app (the launch shim stays; it's inert without the app).
# Does NOT remove TCC grants — those stay in the TCC database until the user removes
# them manually in System Settings, which is fine (a removed .app's grants are just dead rows).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

APP="$HERE/Handlebars.app"
if [ -d "$APP" ]; then
  rm -rf "$APP"
  echo "Handlebars.app removed. TCC grants for it are now inert (remove them in System Settings"
  echo "  if you want a clean slate). Re-run install.sh to rebuild — but that means re-granting"
  echo "  every TCC domain from scratch."
else
  echo "Handlebars.app not found — nothing to remove."
fi
