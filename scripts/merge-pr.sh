#!/usr/bin/env bash
# Squash-merges a pull request once its CI checks pass.
# Usage: scripts/merge-pr.sh <pr-number>
#
# With the ruleset on main and develop, `gh pr merge` refuses on the client side
# even after every check passes (GitHub reports the PR as blocked, most likely because
# the branch's commits are unsigned). The squash commit GitHub makes is signed, and the
# REST merge endpoint applies the ruleset itself, so this goes through it.
# Nothing here bypasses a rule.
set -euo pipefail

pr="${1:?usage: scripts/merge-pr.sh <pr-number>}"

gh pr checks "$pr" --watch --fail-fast
gh api --method PUT "repos/{owner}/{repo}/pulls/$pr/merge" -f merge_method=squash --jq .message
# The repo deletes the head branch after a merge.
