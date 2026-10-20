#!/usr/bin/env bash
# Makes an unsigned Release archive for a real iPhone and checks what would go to App Store
# Connect (Phase 18, docs/testflight.md).
# Usage: scripts/check-archive.sh [archive-path]
#        (default build/Archives/NiftyOutfitNook-unsigned.xcarchive)
#
# Signing is off (CODE_SIGNING_ALLOWED=NO), so it needs no team or certificate, and the
# archive it makes can't be uploaded. Jose's signed archive from Xcode is built from the same
# settings, plus his team. It checks:
# - Info.plist: bundle ID, version and a whole-number build number, ITSAppUsesNonExemptEncryption
#   is NO, the icon and launch screen are set, and there's no App Transport Security key, no
#   usage-description (permission) key and no background mode;
# - the privacy manifest is in the app and declares only UserDefaults, reason CA92.1, and (since
#   Phase 21a, for the migration's free-space check) disk space, reason E174.1;
# - the entitlements file asks for Data Protection (complete) and nothing else;
# - no test bundle, framework or plug-in is in the app, the binary doesn't link XCTest, Swift
#   Testing or swift-snapshot-testing, and it holds no path from the Mac it was built on;
# - scripts/check-release.sh on the device binary (no catalog, benchmark or debug flags);
# - a dSYM was made; then it prints the sizes.
set -euo pipefail
cd "$(dirname "$0")/.."

archive="${1:-build/Archives/NiftyOutfitNook-unsigned.xcarchive}"
rm -rf "$archive"

SECONDS=0
xcodebuild archive \
    -project NiftyOutfitNook.xcodeproj \
    -scheme NiftyOutfitNook \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$archive" \
    -derivedDataPath build/DerivedData \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO \
    -quiet
echo "Archived in ${SECONDS}s: $archive"

app="$archive/Products/Applications/NiftyOutfitNook.app"
binary="$app/NiftyOutfitNook"
failed=0
fail() {
    echo "FAIL: $1" >&2
    failed=1
}

# Info.plist, the privacy manifest and the entitlements, read with plistlib.
python3 - "$app/Info.plist" "$app/PrivacyInfo.xcprivacy" "NiftyOutfitNook/NiftyOutfitNook.entitlements" <<'PY' || failed=1
import plistlib
import re
import sys

info_path, privacy_path, entitlements_path = sys.argv[1:4]
problems = []

with open(info_path, "rb") as f:
    info = plistlib.load(f)
expected = {
    "CFBundleIdentifier": "com.jsayram.niftyoutfitnook",
    "CFBundleDisplayName": "Outfit Nook",
    "CFBundleShortVersionString": "0.1.0",
    "ITSAppUsesNonExemptEncryption": False,
    "MinimumOSVersion": "26.0",
}
for key, value in expected.items():
    if info.get(key) != value:
        problems.append(f"Info.plist {key} is {info.get(key)!r}, expected {value!r}")
build = info.get("CFBundleVersion", "")
if not re.fullmatch(r"[0-9]+(\.[0-9]+){0,2}", build):
    problems.append(f"build number {build!r} isn't one to three whole numbers")
if info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconName") != "AppIcon":
    problems.append("no AppIcon in CFBundleIcons")
if info.get("UILaunchScreen", {}).get("UIColorName") != "LaunchBackground":
    problems.append("the launch screen isn't the LaunchBackground colour")
for key in info:
    if key == "NSAppTransportSecurity":
        problems.append("Info.plist has an App Transport Security key")
    if key.endswith("UsageDescription"):
        problems.append(f"Info.plist asks for a permission: {key}")
    if key == "UIBackgroundModes":
        problems.append("Info.plist has background modes")

with open(privacy_path, "rb") as f:
    privacy = plistlib.load(f)
if privacy.get("NSPrivacyTracking") is not False:
    problems.append("privacy manifest: NSPrivacyTracking isn't false")
if privacy.get("NSPrivacyTrackingDomains") or privacy.get("NSPrivacyCollectedDataTypes"):
    problems.append("privacy manifest lists tracking domains or collected data")
apis = {
    item["NSPrivacyAccessedAPIType"]: item["NSPrivacyAccessedAPITypeReasons"]
    for item in privacy.get("NSPrivacyAccessedAPITypes", [])
}
if apis != {
    "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
    "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
}:
    problems.append(f"privacy manifest APIs changed: {apis}")

with open(entitlements_path, "rb") as f:
    entitlements = plistlib.load(f)
if entitlements != {"com.apple.developer.default-data-protection": "NSFileProtectionComplete"}:
    problems.append(f"entitlements changed: {entitlements}")

for problem in problems:
    print(f"FAIL: {problem}", file=sys.stderr)
if problems:
    sys.exit(1)
print(f"Info.plist, privacy manifest and entitlements: as expected (build {build})")
PY

# Nothing from the tests ships.
extras="$(find "$app" \( -name '*.xctest' -o -name 'Frameworks' -o -name 'PlugIns' -o -iname '*snapshot*' \) -print)"
if [[ -n "$extras" ]]; then
    fail "the app contains test code, frameworks or plug-ins: $extras"
fi
if otool -L "$binary" | grep -E -i "xctest|/Testing\.framework|snapshot"; then
    fail "the binary links a test framework"
fi
# Not `strings | grep -q`: under pipefail, grep stopping early makes strings die of SIGPIPE and the
# check pass by mistake (Phase 20a).
if grep -q "/Users/" <<<"$(strings "$binary")"; then
    fail "the binary holds a path from the build Mac"
fi
scripts/check-release.sh "$binary" || failed=1

dsym="$archive/dSYMs/NiftyOutfitNook.app.dSYM"
if [[ ! -d "$dsym" ]]; then
    fail "no dSYM in the archive"
fi

if [[ $failed -ne 0 ]]; then
    exit 1
fi
echo "Sizes: app $(du -sh "$app" | cut -f1), binary $(du -sh "$binary" | cut -f1), dSYM $(du -sh "$dsym" | cut -f1)"
echo "The archive is ready to check by hand: $archive"
