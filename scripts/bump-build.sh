#!/usr/bin/env bash
# Sets the build number for the next archive (Phase 18, docs/testflight.md).
# Usage: scripts/bump-build.sh          the current UTC date and time, for example 20261016.1420
#        scripts/bump-build.sh <number> a number of your own, for example 20261016.1500
#
# Writes CURRENT_PROJECT_VERSION to Configs/Build.local.xcconfig, which git ignores and which
# Configs/Version.xcconfig includes. App Store Connect needs a higher build number for every
# upload of the same version; a timestamp only goes up, on any Mac, with nothing to commit.
# The time part has no leading zero (09:05 is 905), since each part of a build number is read
# as a whole number: 905 still sorts before 1420. UTC, so a clock change can't go backwards.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -gt 0 ]]; then
    build="$1"
else
    build="$(date -u +%Y%m%d).$((10#$(date -u +%H%M)))"
fi
if [[ ! "$build" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "A build number is one to three whole numbers joined by dots, not '$build'." >&2
    exit 1
fi

file="Configs/Build.local.xcconfig"
{
    echo "// Written by scripts/bump-build.sh. Ignored by git."
    echo "CURRENT_PROJECT_VERSION = $build"
} > "$file"
echo "Build number $build (in $file). Archive now; Help in the app will show it."
