# Agent notes

The spec for this app lives in the separate planning repo, `closet` (https://github.com/jsayram/closet). Read these there before working here:

- `SWIFT_BUILD_PLAN.md`: the phase list, how we work, the definition of done, and branching.
- `SECURITY_STANDARD.md`: required, with no exceptions unless Jose approves one in writing.
- `IOS_APP_PLAYBOOK.md`: reusable lessons. Add only things that were verified.
- `Nifty_Outfit_Nook_PRD_v2.md` and `PRD_Amendment_Room_Direction.md`: the product requirements.

In this repo:

- `docs/decisions/0001-technical-decisions.md` is approved and binding.
- This repo is public. No backend code, prompts, fit or styling rules, model config, keys, tokens or secrets.
- Run `scripts/install-hooks.sh` once per clone, so the gitleaks pre-commit hook runs.
- Work on `feature/<phase>-<name>` off `develop`. `main` and `develop` are protected for everyone: open a PR into `develop`, wait for CI with `gh pr checks <number> --watch`, then merge with `scripts/merge-pr.sh <number>`.
- Why the script: with the ruleset on, `gh pr merge` refuses on its own side ("base branch policy prohibits the merge") even when every check has passed. GitHub reports the PR as blocked, most likely because the branch's own commits are unsigned, while the squash commit GitHub makes is signed and passes the ruleset. The script squash-merges through the REST API instead, and GitHub then deletes the branch. Never use `--admin`.
- Before merging, merge the latest `develop` into your branch, push, and wait for green CI on that exact commit, then run `scripts/merge-pr.sh`. CI only tests your branch as it stands, so if `develop` moved during the run, green checks don't cover the merged result (PR #78 landed after #79 and broke `develop` for 33 minutes). The script now refuses with "develop moved" if the PR head lacks the current `develop` tip, or if the head changed while it waited. `scripts/merge-pr.sh --dry-run <n>` runs the checks without merging, and `scripts/test-merge-pr.sh` tests the guard with a fake `gh`.
- Before a PR: `scripts/format.sh` and `scripts/test.sh` pass.
- Milestone promotions to `main` (end of Phase 3, before 18, after 21, after 30, release): open the PR with `scripts/promote.sh`, not from `develop` directly. Squash-only merging means `main` and `develop` share no history after the first promotion, so a PR from `develop` would conflict. The script explains why. The PR body walks the security review gate in `closet/SECURITY_STANDARD.md` §11.
