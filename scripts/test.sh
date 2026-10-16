#!/usr/bin/env bash
# Runs every test: the NookKit package tests and the UI tests, on an iPhone simulator.
# See scripts/simulator.sh for how the simulator is chosen. NOOK_SIM_FAMILY=iPad picks an iPad
# instead, for the iPad UI tests (Phase 15a, docs/ipad.md):
#   NOOK_SIM_FAMILY=iPad scripts/test.sh -only-testing:NiftyOutfitNookUITests/IPadTests
#
# Usage: scripts/test.sh [xcodebuild test selection...]
# With no arguments it runs the whole test plan. Arguments go to `xcodebuild test-without-building`,
# so CI can split the suite, for example:
#   scripts/test.sh -skip-testing:NiftyOutfitNookUITests          # package tests only
#   scripts/test.sh -only-testing:NiftyOutfitNookUITests/HomeTests # one UI test class
#
# It builds once with build-for-testing, then tests without building, and prints how long each
# step took. xcodebuild boots the simulator itself: waiting for a full boot first with
# `simctl bootstatus` took 2 to 4 minutes on CI, against about a minute for xcodebuild's own boot.
set -euo pipefail
cd "$(dirname "$0")/.."

simulator_id="$(scripts/simulator.sh)"

# On CI (GitHub Actions sets CI), tell the tests so the speed checks allow for a slower, shared
# runner. xcodebuild passes TEST_RUNNER_* variables to the tests without the prefix.
if [[ -n "${CI:-}" ]]; then
    export TEST_RUNNER_NOOK_CI=1
fi
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
rm -rf "$result_bundle"
status=0
xcodebuild test-without-building "${common[@]}" -resultBundlePath "$result_bundle" "$@" || status=$?
echo "Tested in ${SECONDS}s"
exit $status
