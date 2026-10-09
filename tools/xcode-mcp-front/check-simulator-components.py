#!/usr/bin/env python3
"""Compare the selected Xcode's shared framework versions with the installed copies.

Inputs: DEVELOPER_DIR, or xcode-select's active developer directory.
Output: package, receipt, and framework versions; exit 2 on a mismatch.
Requires macOS, xar, pkgutil, and the selected Xcode's system resources package.
"""

import os
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


RECEIPT = "com.apple.pkg.XcodeSystemResources"
FRAMEWORK_IDS = {
    "CoreSimulator": "com.apple.CoreSimulator",
    "CoreDevice": "com.apple.CoreDevice",
    "CoreDeviceUtilities": "com.apple.dt.CoreDevice.Utilities",
}
FRAMEWORK_ROOT = Path("/Library/Developer/PrivateFrameworks")


def command(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd)


def main():
    developer_dir = Path(os.environ.get("DEVELOPER_DIR") or command("xcode-select", "-p").decode().strip())
    if developer_dir.name != "Developer" or developer_dir.parent.name != "Contents":
        raise ValueError(f"Expected an Xcode developer directory, got {developer_dir}")
    package = developer_dir.parent.parent / "Contents/Resources/Packages/XcodeSystemResources.pkg"
    if not package.is_file():
        raise FileNotFoundError(package)

    with tempfile.TemporaryDirectory(prefix="xcode-system-resources-") as scratch:
        command("xar", "-x", "-f", str(package), "PackageInfo", cwd=scratch)
        root = ET.parse(Path(scratch) / "PackageInfo").getroot()
        package_version = root.attrib["version"]
        package_frameworks = {
            name: next(
                element.attrib["CFBundleVersion"]
                for element in root.findall(".//bundle")
                if element.attrib.get("id") == identifier
                and "CFBundleVersion" in element.attrib
            )
            for name, identifier in FRAMEWORK_IDS.items()
        }

    receipt = plistlib.loads(command("pkgutil", "--pkg-info-plist", RECEIPT))
    installed_frameworks = {}
    for name in FRAMEWORK_IDS:
        info = FRAMEWORK_ROOT / f"{name}.framework/Resources/Info.plist"
        with info.open("rb") as file:
            installed_frameworks[name] = plistlib.load(file)["CFBundleVersion"]
    receipt_version = receipt["pkg-version"]

    print(f"Selected Xcode: {developer_dir.parent.parent}")
    print(f"Selected package: {package_version}")
    print(f"Installed receipt: {receipt_version}")
    for name in FRAMEWORK_IDS:
        print(f"{name}: package {package_frameworks[name]}, installed {installed_frameworks[name]}")
    if package_version != receipt_version or package_frameworks != installed_frameworks:
        print("MISMATCH: installed simulator components differ from the selected Xcode.")
        return 2
    print("MATCH: installed simulator components match the selected Xcode.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, StopIteration, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f"check-simulator-components: {error}", file=sys.stderr)
        sys.exit(1)
