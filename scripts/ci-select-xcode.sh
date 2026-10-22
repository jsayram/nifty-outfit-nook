#!/usr/bin/env bash
# CI only: picks the Xcode app for this job and points the rest of the job at it.
# Usage: scripts/ci-select-xcode.sh
#
# Uses $XCODE_APP (the CI workflow sets it to /Applications/Xcode_27.1.app, which is where
# GitHub's xcode-27 image has Xcode 27.1) if that exists, and otherwise /Applications/Xcode.app,
# which is where it is on the self-hosted runner (Jose's Mac). It sets DEVELOPER_DIR for the later
# steps, and doesn't run `sudo xcode-select --switch`: the self-hosted runner has no passwordless
# sudo, and a CI job must not change a system setting on that Mac.
set -euo pipefail

app=""
for candidate in "${XCODE_APP:-}" /Applications/Xcode.app; do
    if [[ -n "$candidate" && -d "$candidate/Contents/Developer" ]]; then
        app="$candidate"
        break
    fi
done
if [[ -z "$app" ]]; then
    echo "No Xcode found (looked for \$XCODE_APP=${XCODE_APP:-unset} and /Applications/Xcode.app)" >&2
    exit 1
fi

export DEVELOPER_DIR="$app/Contents/Developer"
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"
fi
echo "Xcode: $app"
xcodebuild -version
# The README names the Xcode version the project is built and tested with.
if ! xcodebuild -version | head -1 | grep -q '^Xcode 27\.1'; then
    echo "::warning::This job is not on Xcode 27.1. Snapshot references and the test results assume it."
fi
