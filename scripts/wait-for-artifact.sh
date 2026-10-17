#!/usr/bin/env bash
# CI only: waits until another job in this workflow run has uploaded an artifact.
# Usage: scripts/wait-for-artifact.sh <artifact name> <name of the job that uploads it>
#
# The UI test jobs start with the build job instead of after it, so each can boot its simulator
# while the build runs, then test what the build uploaded (see .github/workflows/ci.yml). This
# asks the GitHub API about this run only (GITHUB_RUN_ID), so it can't pick up another run's
# artifact. Needs GH_TOKEN with actions: read.
#
# It writes `ready=true` to GITHUB_OUTPUT once the artifact is there. If the build job is still
# queued after 3 minutes (the free plan's five macOS runners are busy, perhaps with these test
# jobs themselves), it writes `ready=false` instead, so the test job builds for itself rather
# than wait for a runner it may be holding. It fails when the build job ended without
# uploading, or after 20 minutes.
set -euo pipefail

name="${1:?usage: scripts/wait-for-artifact.sh <artifact> <job>}"
job="${2:?usage: scripts/wait-for-artifact.sh <artifact> <job>}"
run="repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"

# A failed API call (CI once got a TLS handshake timeout) counts as "not yet", never as "yes".
uploaded() {
    local count
    count="$(gh api "$run/artifacts?name=$name" --jq '.total_count')" || return 1
    [[ "$count" =~ ^[0-9]+$ ]] && ((count > 0))
}

SECONDS=0
while ((SECONDS < 1200)); do
    if uploaded; then
        echo "$name is ready after ${SECONDS}s"
        echo "ready=true" >> "$GITHUB_OUTPUT"
        exit 0
    fi
    status="$(gh api "$run/attempts/$GITHUB_RUN_ATTEMPT/jobs" --jq ".jobs[] | select(.name == \"$job\") | .status")" ||
        status=""
    if [[ "$status" == "completed" ]] && ! uploaded; then
        echo "$job ended without uploading $name" >&2
        exit 1
    fi
    if [[ "$status" == "queued" || "$status" == "waiting" || "$status" == "pending" ]] && ((SECONDS >= 180)); then
        echo "$job hasn't started after ${SECONDS}s ($status), so this job builds for itself"
        echo "ready=false" >> "$GITHUB_OUTPUT"
        exit 0
    fi
    sleep 10
done
echo "No $name after ${SECONDS}s" >&2
exit 1
