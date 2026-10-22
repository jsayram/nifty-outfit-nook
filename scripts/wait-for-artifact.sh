#!/usr/bin/env bash
# CI only: waits until another job in this workflow run has uploaded an artifact.
# Usage: scripts/wait-for-artifact.sh <artifact name> <name of the job that uploads it> [<name of its upload step>]
#
# The UI test jobs start with the build job instead of after it, so each can boot its simulator
# while the build runs, then test what the build uploaded (see .github/workflows/ci.yml). This
# asks the GitHub API about this run only (GITHUB_RUN_ID), so it can't pick up another run's
# artifact. Needs GH_TOKEN with actions: read.
#
# It writes `ready=true` to GITHUB_OUTPUT once the artifact is there. If the build job is still
# queued after 3 minutes, it writes `ready=false` instead, so the test job builds for itself
# rather than wait for a runner it may be holding. That is also the break-even point: a hosted
# job builds the UI tests in about 4 minutes, and the Mac's build job uploads within a minute of
# starting. A queue longer than 3 minutes happens when the Mac is still busy with the run that a
# merge started (the batch is usually started right after one). It fails when the build job ended
# without uploading, or after 20 minutes.
#
# The artifact list can trail the upload (run 39853441466: the artifact was created at 21:03:17,
# and one test job saw it at 21:10:02). So the build job's upload step finishing counts too, and
# the artifact list gets 45 more seconds to catch up. Every minute this prints what it sees, so
# a slow wait can be explained from the log.
set -euo pipefail

name="${1:?usage: scripts/wait-for-artifact.sh <artifact> <job> [<upload step>]}"
job="${2:?usage: scripts/wait-for-artifact.sh <artifact> <job> [<upload step>]}"
step="${3:-}"
run="repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"

# A failed API call (CI once got a TLS handshake timeout) counts as "not yet", never as "yes".
uploaded() {
    local count
    count="$(gh api "$run/artifacts?name=$name" --jq '.total_count')" || return 1
    [[ "$count" =~ ^[0-9]+$ ]] && ((count > 0))
}

# The build job's status, and whether its upload step has finished successfully, as "status<TAB>0|1".
# Empty when the call failed.
build_job() {
    gh api "$run/attempts/$GITHUB_RUN_ATTEMPT/jobs" --jq \
        ".jobs[] | select(.name == \"$job\") | [.status, ([.steps[]? | select(.name == \"$step\" and .conclusion == \"success\")] | length | if . > 0 then 1 else 0 end)] | @tsv" ||
        true
}

SECONDS=0
step_done_at=""
last_report=0
while ((SECONDS < 1200)); do
    listed=false
    if uploaded; then listed=true; fi
    info="$(build_job)"
    status="${info%%$'\t'*}"
    step_done="${info##*$'\t'}"
    if [[ "$listed" == "true" ]]; then
        echo "$name is ready after ${SECONDS}s"
        echo "ready=true" >> "$GITHUB_OUTPUT"
        exit 0
    fi
    if [[ -n "$step" && "$step_done" == "1" ]]; then
        [[ -n "$step_done_at" ]] || step_done_at=$SECONDS
        if ((SECONDS - step_done_at >= 45)); then
            echo "$name is ready after ${SECONDS}s ($job finished uploading it ${step_done_at}s in, but the artifact list still doesn't show it)"
            echo "ready=true" >> "$GITHUB_OUTPUT"
            exit 0
        fi
    fi
    if [[ "$status" == "completed" ]] && ! uploaded; then
        echo "$job ended without uploading $name" >&2
        exit 1
    fi
    if [[ "$status" == "queued" || "$status" == "waiting" || "$status" == "pending" ]] && ((SECONDS >= 180)); then
        echo "$job hasn't started after ${SECONDS}s ($status), so this job builds for itself"
        echo "ready=false" >> "$GITHUB_OUTPUT"
        exit 0
    fi
    if ((SECONDS - last_report >= 60)); then
        last_report=$SECONDS
        echo "${SECONDS}s: $job is '${status:-unknown}', upload step finished: ${step_done:-unknown}, artifact listed: $listed"
    fi
    sleep 10
done
echo "No $name after ${SECONDS}s" >&2
exit 1
