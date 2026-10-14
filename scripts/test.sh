#!/usr/bin/env bash
# Runs every test: the NookKit package tests and the UI tests, on an iPhone simulator.
# See scripts/simulator.sh for how the simulator is chosen.
#
# Usage: scripts/test.sh [xcodebuild test selection...]
# With no arguments it runs the whole test plan. Arguments go to `xcodebuild test-without-building`,
# so CI can split the suite, for example:
#   scripts/test.sh -skip-testing:NiftyOutfitNookUITests          # package tests only
#   scripts/test.sh -only-testing:NiftyOutfitNookUITests/HomeTests # one UI test class
#
# It builds once with build-for-testing, then tests without building. The simulator boots in the
# background while the build runs, instead of after it.
set -euo pipefail
cd "$(dirname "$0")/.."

simulator_id="$(scripts/simulator.sh)"
result_bundle="${NOOK_RESULT_BUNDLE:-build/TestResults.xcresult}"
echo "Testing on simulator $simulator_id"

# Boot in the background so it overlaps the build. A simulator that's already booted just says so.
(xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true) &

common=(
    -project NiftyOutfitNook.xcodeproj
    -scheme NiftyOutfitNook
    -destination "id=$simulator_id"
    -derivedDataPath build/DerivedData
    -onlyUsePackageVersionsFromResolvedFile
)

xcodebuild build-for-testing "${common[@]}" -quiet
echo "Built for testing"

wait
xcrun simctl bootstatus "$simulator_id" -b >/dev/null
rm -rf "$result_bundle"
xcodebuild test-without-building "${common[@]}" -resultBundlePath "$result_bundle" "$@"
