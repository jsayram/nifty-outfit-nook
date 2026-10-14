#!/usr/bin/env bash
# Checks that the two Package.resolved files pin the same versions.
#
# Xcode builds read NiftyOutfitNook.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved.
# SwiftPM and Dependabot read Packages/NookKit/Package.resolved. Both are committed, and they
# must agree. After changing a dependency, resolve both:
#   (cd Packages/NookKit && swift package resolve)
#   xcodebuild -resolvePackageDependencies -project NiftyOutfitNook.xcodeproj -scheme NiftyOutfitNook
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, sys

def pins(path):
    with open(path) as file:
        return {pin["identity"]: (pin["location"], pin["state"].get("version"), pin["state"]["revision"])
                for pin in json.load(file)["pins"]}

package = pins("Packages/NookKit/Package.resolved")
xcode = pins("NiftyOutfitNook.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
if package != xcode:
    for name in sorted(set(package) | set(xcode)):
        if package.get(name) != xcode.get(name):
            print(f"{name}: package {package.get(name)} vs Xcode {xcode.get(name)}", file=sys.stderr)
    sys.exit("The two Package.resolved files disagree. See scripts/check-package-pins.sh.")
print(f"Package.resolved files agree ({len(package)} pins)")
PY
