#!/usr/bin/env bash
# Builds the app and the NookKit package for the iOS Simulator.
# Usage: scripts/build.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-Debug}"

xcodebuild build \
    -project NiftyOutfitNook.xcodeproj \
    -scheme NiftyOutfitNook \
    -configuration "$configuration" \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath build/DerivedData \
    -quiet
echo "Build succeeded ($configuration)"
