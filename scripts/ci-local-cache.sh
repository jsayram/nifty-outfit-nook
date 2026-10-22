#!/usr/bin/env bash
# CI on the self-hosted runner only: keeps DerivedData (and with it the SwiftPM checkouts)
# between jobs, so a build starts from the last one instead of from nothing.
# Usage: scripts/ci-local-cache.sh
#
# The scripts build into build/DerivedData, and actions/checkout deletes build/ before every job.
# This links build/DerivedData to a folder inside the runner's _work folder, which survives. Only
# jobs from this repository's own branches reach a self-hosted runner (see the README, "CI"),
# and the runner runs one job at a time, so jobs never share the folder at the same moment.
#
# NOOK_CI_COLD=1 empties the folder first, once per workflow run, for a cold-cache measurement.
# Stale .xctestrun files are removed: the build writes the ones the job needs, and the test
# steps expect exactly one match.
set -euo pipefail
cd "$(dirname "$0")/.."

workspace_parent="$(cd "${RUNNER_WORKSPACE:?CI only}/.." && pwd)"
cache="$workspace_parent/_cache/DerivedData"
mkdir -p "$cache" build

if [[ -n "${NOOK_CI_COLD:-}" ]]; then
    marker="$workspace_parent/_cache/cold-run-${GITHUB_RUN_ID:-0}-${GITHUB_RUN_ATTEMPT:-0}"
    if [[ ! -e "$marker" ]]; then
        echo "Cold run: emptying $cache"
        rm -rf "$cache"
        mkdir -p "$cache"
        rm -f "$workspace_parent"/_cache/cold-run-*
        touch "$marker"
    fi
fi

rm -rf build/DerivedData
ln -s "$cache" build/DerivedData
rm -f "$cache"/Build/Products/*.xctestrun
echo "DerivedData: build/DerivedData -> $cache ($(du -sh "$cache" | cut -f1))"
