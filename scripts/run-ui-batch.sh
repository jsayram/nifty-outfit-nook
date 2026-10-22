#!/usr/bin/env bash
# Starts the batch UI run: the CI workflow run by hand (workflow_dispatch) on develop, which
# runs the whole UI suite on an iPhone simulator, and prints the run's URL.
# Usage: scripts/run-ui-batch.sh [--ipad] [--ref <branch>]
#
# UI tests no longer run on every pull request (22 October 2026). A pull request runs the fast gate
# (format, gitleaks, build and archive check, every package test). The UI tests run when a pull
# request has the `run-ui` label, and in this batch on develop, after about every three
# UI-touching merges and at phase milestones. If a batch fails, bisect the commits it covers.
#
#   --ipad        Also run the iPad parts (the iPad UI tests and the iPad snapshot tests). iPad
#                 testing is paused until the app's features are done.
#   --ref <name>  Run on another branch instead of develop (for trying a workflow change).
#
# The run starts on the branch's tip as GitHub has it, which is what this prints, so push first if
# you mean local commits. Needs the gh CLI, signed in with access to the repo's Actions.
set -euo pipefail

ref=develop
ipad=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ipad) ipad=true; shift ;;
    --ref) ref="${2:?--ref needs a branch name}"; shift 2 ;;
    *) echo "usage: scripts/run-ui-batch.sh [--ipad] [--ref <branch>]" >&2; exit 2 ;;
  esac
done

tip="$(gh api "repos/{owner}/{repo}/git/ref/heads/$ref" --jq .object.sha)"
echo "Starting the batch UI run on $ref at ${tip:0:9} (iPad: $ipad)."
# 30 seconds back, so a few seconds of clock difference with GitHub can't hide the new run.
started="$(date -u -v-30S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 seconds ago' +%Y-%m-%dT%H:%M:%SZ)"
gh workflow run ci.yml --ref "$ref" -f "include_ipad=$ipad"

# The run takes a few seconds to appear. Look for the one made after the dispatch, for this commit.
for _ in $(seq 1 30); do
  url="$(gh run list --workflow ci.yml --event workflow_dispatch --branch "$ref" --limit 10 \
    --json url,headSha,createdAt \
    --jq "[.[] | select(.headSha == \"$tip\" and .createdAt >= \"$started\")] | sort_by(.createdAt) | last | .url // empty")"
  if [[ -n "$url" ]]; then
    echo "$url"
    echo "Wait for it with: gh run watch ${url##*/} --exit-status --interval 60"
    exit 0
  fi
  sleep 3
done
echo "The run was requested, but it did not show up in the list yet. Check: gh run list --workflow ci.yml --event workflow_dispatch --branch $ref" >&2
exit 1
