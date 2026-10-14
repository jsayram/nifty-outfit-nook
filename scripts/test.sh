#!/usr/bin/env bash
# Runs every test: the NookKit package tests and the UI tests, on an iPhone simulator.
# See scripts/simulator.sh for how the simulator is chosen.
set -euo pipefail
cd "$(dirname "$0")/.."

simulator_id="$(scripts/simulator.sh)"
result_bundle="build/TestResults.xcresult"
echo "Testing on simulator $simulator_id"

rm -rf "$result_bundle"
xcodebuild test \
    -project NiftyOutfitNook.xcodeproj \
    -scheme NiftyOutfitNook \
    -destination "id=$simulator_id" \
    -derivedDataPath build/DerivedData \
    -resultBundlePath "$result_bundle"
