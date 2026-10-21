#!/usr/bin/env bash
# Squash-merges a pull request once its CI checks pass.
# Usage: scripts/merge-pr.sh [--dry-run] <pr-number>
#
# With the ruleset on main and develop, `gh pr merge` refuses on the client side
# even after every check passes (GitHub reports the PR as blocked, most likely because
# the branch's commits are unsigned). The squash commit GitHub makes is signed, and the
# REST merge endpoint applies the ruleset itself, so this goes through it.
# Nothing here bypasses a rule.
#
# Stale-base guard: CI only tests the PR branch as it is. If the base branch moved
# while CI ran (PR #78 merged after #79 landed and broke develop for 33 minutes), the
# green checks say nothing about the merged result. So the script refuses unless the
# PR head already contains the current tip of the base branch, and it pins the merge
# to the head SHA that the checks ran on (GitHub rejects the merge if the head changed).
# --dry-run runs every check and stops before the merge.
set -euo pipefail

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
  shift
fi
pr="${1:?usage: scripts/merge-pr.sh [--dry-run] <pr-number>}"

refuse_if_base_moved() {
  local base="$1" head_sha="$2" base_tip status
  base_tip="$(gh api "repos/{owner}/{repo}/git/ref/heads/$base" --jq .object.sha)"
  status="$(gh api "repos/{owner}/{repo}/compare/$base_tip...$head_sha" --jq .status)"
  # "ahead" or "identical": the head contains the base tip. Anything else: the base has commits the head lacks.
  if [[ "$status" != "ahead" && "$status" != "identical" ]]; then
    echo "REFUSING TO MERGE PR #$pr: $base moved: merge origin/$base into your branch, push, and wait for CI." >&2
    echo "  $base is at ${base_tip:0:9}, which is not in the PR head ${head_sha:0:9} (compare status: $status)." >&2
    exit 1
  fi
}

read -r base head_sha < <(gh pr view "$pr" --json baseRefName,headRefOid --jq '"\(.baseRefName) \(.headRefOid)"')
refuse_if_base_moved "$base" "$head_sha"

gh pr checks "$pr" --watch --fail-fast

# The wait can be long. Confirm nothing moved while CI ran, so the green checks belong
# to this exact head and this head still contains the current base tip.
read -r base_now head_now < <(gh pr view "$pr" --json baseRefName,headRefOid --jq '"\(.baseRefName) \(.headRefOid)"')
if [[ "$head_now" != "$head_sha" ]]; then
  echo "REFUSING TO MERGE PR #$pr: the head changed from ${head_sha:0:9} to ${head_now:0:9} during the CI wait. Wait for CI on the new commit and run this again." >&2
  exit 1
fi
refuse_if_base_moved "$base_now" "$head_sha"

if [[ "$dry_run" == 1 ]]; then
  echo "Dry run: PR #$pr is up to date with $base_now and its checks are green on ${head_sha:0:9}. Not merging."
  exit 0
fi

# sha= makes GitHub reject the merge if the head is no longer the commit the checks ran on.
gh api --method PUT "repos/{owner}/{repo}/pulls/$pr/merge" -f merge_method=squash -f sha="$head_sha" --jq .message
# The repo deletes the head branch after a merge.
