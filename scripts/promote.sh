#!/usr/bin/env bash
# Opens the pull request that promotes develop to main at a milestone.
# Usage: scripts/promote.sh "<title>" <body-file>
#        PROMOTE_DRY_RUN=1 scripts/promote.sh "<title>" <body-file>   shows the diff, pushes nothing
#
# Why not a PR straight from develop: the ruleset allows only squash merges with linear
# history, so after the first promotion main and develop share no commits past the repo's
# first one. A PR from develop would merge against that old ancestor and conflict on every
# file changed since. Instead this makes one commit on top of main whose files are exactly
# develop's, pushes it as promote/<date>, and opens the PR from there. The PR's diff is then
# just what changed since the last promotion. Merge it with scripts/merge-pr.sh as usual.
set -euo pipefail
cd "$(dirname "$0")/.."

title="${1:?usage: scripts/promote.sh \"<title>\" <body-file>}"
body="${2:?usage: scripts/promote.sh \"<title>\" <body-file>}"

git fetch --quiet origin main develop
develop_tree="$(git rev-parse 'origin/develop^{tree}')"
if [[ "$develop_tree" == "$(git rev-parse 'origin/main^{tree}')" ]]; then
    echo "main already has the same files as develop. Nothing to promote."
    exit 0
fi

develop_short="$(git rev-parse --short origin/develop)"
commit="$(git commit-tree "$develop_tree" -p origin/main -m "Promote develop at $develop_short to main")"
echo "Promotion commit $commit on top of main. Changes since the last promotion:"
git diff --stat origin/main "$commit" | tail -n 20

if [[ -n "${PROMOTE_DRY_RUN:-}" ]]; then
    echo "Dry run: nothing pushed."
    exit 0
fi

branch="promote/$(date +%Y-%m-%d)-$develop_short"
git push origin "$commit:refs/heads/$branch"
gh pr create --base main --head "$branch" --title "$title" --body-file "$body"
