#!/bin/bash
set -euo pipefail

# Reinstall the CoreSimulator/CoreDevice frameworks from the selected Xcode.
# Run with sudo. The previous framework bundles stay in a backup folder.
# This closes Xcode and Device Hub, including any running simulator windows.

here=$(cd -- "$(dirname -- "$0")" && pwd)
check="$here/check-simulator-components.py"
developer_dir=$(/usr/bin/xcode-select -p)
package="$developer_dir/../Resources/Packages/XcodeSystemResources.pkg"
frameworks=/Library/Developer/PrivateFrameworks
names=(CoreSimulator CoreDevice CoreDeviceUtilities)

if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi
if [[ ! -f $package ]]; then
  echo "Missing selected Xcode package: $package" >&2
  exit 1
fi
if DEVELOPER_DIR="$developer_dir" /usr/bin/python3 "$check"; then
  echo "No repair needed."
  exit 0
fi
for name in "${names[@]}"; do
  if [[ ! -d $frameworks/$name.framework ]]; then
    echo "Missing installed framework: $frameworks/$name.framework" >&2
    exit 1
  fi
done

backup=$(/usr/bin/mktemp -d /Library/Developer/XcodeSystemResourcesBackup.XXXXXXXX)
echo "Backup: $backup"

restore() {
  echo "Install or version check failed. Restoring the previous frameworks." >&2
  for name in "${names[@]}"; do
    if [[ -d $backup/$name.framework ]]; then
      if [[ -e $frameworks/$name.framework ]]; then
        /bin/mv "$frameworks/$name.framework" "$backup/partial-$name.framework"
      fi
      /bin/mv "$backup/$name.framework" "$frameworks/$name.framework"
    fi
  done
  echo "Previous frameworks restored. Backup remains at $backup" >&2
}
trap restore EXIT

echo "Stopping Xcode and simulator services."
/usr/bin/osascript -e 'tell application id "com.apple.dt.Xcode" to quit' || true
/usr/bin/killall Xcode || true
/usr/bin/pkill -KILL -x DeviceHub || true
/usr/bin/killall com.apple.CoreSimulator.CoreSimulatorService || true
/bin/sleep 2

for name in "${names[@]}"; do
  /bin/mv "$frameworks/$name.framework" "$backup/$name.framework"
done

echo "Installing system resources from $developer_dir"
/usr/sbin/installer -pkg "$package" -target /
DEVELOPER_DIR="$developer_dir" /usr/bin/python3 "$check"

trap - EXIT
echo "Selected Xcode's shared frameworks are installed. Backup remains at $backup"
