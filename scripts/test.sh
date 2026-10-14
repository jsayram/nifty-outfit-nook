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
# It builds once with build-for-testing, then boots the simulator and tests without building.
# Each step prints how long it took, so slow CI runs are easy to read.
set -euo pipefail
cd "$(dirname "$0")/.."

simulator_id="$(scripts/simulator.sh)"
result_bundle="${NOOK_RESULT_BUNDLE:-build/TestResults.xcresult}"
echo "Testing on simulator $simulator_id"

common=(
    -project NiftyOutfitNook.xcodeproj
    -scheme NiftyOutfitNook
    -destination "id=$simulator_id"
    -derivedDataPath build/DerivedData
    -onlyUsePackageVersionsFromResolvedFile
)

SECONDS=0
xcodebuild build-for-testing "${common[@]}" -quiet
echo "Built for testing in ${SECONDS}s"

SECONDS=0
xcrun simctl bootstatus "$simulator_id" -b >/dev/null
echo "Simulator booted in ${SECONDS}s"
rm -rf "$result_bundle"
xcodebuild test-without-building "${common[@]}" -resultBundlePath "$result_bundle" "$@"
