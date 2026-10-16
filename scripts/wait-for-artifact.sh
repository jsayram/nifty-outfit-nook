#!/usr/bin/env bash
# CI only: waits until another job in this workflow run has uploaded an artifact.
# Usage: scripts/wait-for-artifact.sh <artifact name> <name of the job that uploads it>
#
# The UI test jobs start with the build job instead of after it, so each can boot its simulator
# while the build runs, then test what the build uploaded (see .github/workflows/ci.yml). This
# asks the GitHub API about this run only (GITHUB_RUN_ID), so it can't pick up another run's
# artifact. It gives up when the build job has ended without it, or after 20 minutes.
# Needs GH_TOKEN with actions: read.
set -euo pipefail

name="${1:?usage: scripts/wait-for-artifact.sh <artifact> <job>}"
job="${2:?usage: scripts/wait-for-artifact.sh <artifact> <job>}"
run="repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"

SECONDS=0
uploaded() {
    [[ "$(gh api "$run/artifacts?name=$name" --jq '.total_count')" != "0" ]]
}

while ((SECONDS < 1200)); do
    if uploaded; then
        echo "$name is ready after ${SECONDS}s"
        exit 0
    fi
    state="$(gh api "$run/attempts/$GITHUB_RUN_ATTEMPT/jobs" --jq ".jobs[] | select(.name == \"$job\") | .conclusion")"
    if [[ -n "$state" ]] && ! uploaded; then
        echo "$job ended ($state) without uploading $name" >&2
        exit 1
    fi
    sleep 10
done
echo "No $name after ${SECONDS}s" >&2
exit 1
