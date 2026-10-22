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
- CI shape (22 October 2026): a PR runs the fast gate only (format, gitleaks, the build and archive check, every package test). UI tests run with the `run-ui` label on a PR, and in a batch on develop: `scripts/run-ui-batch.sh` starts it and prints the run URL. Run a batch after about every three UI-touching merges and at phase milestones; if one fails, bisect the commits it covers.
- iPad testing is paused until the app's features are done (the iPhone 12 is the main target). The `ui-ipad` job runs only on a manual run with `include_ipad` (`scripts/run-ui-batch.sh --ipad`), and the iPad snapshot tests skip themselves unless `NOOK_IPAD_SNAPSHOTS=1`. They are not deleted. To turn iPad back on, follow "Turning iPad testing back on" under CI in `README.md`.
- Which runner (22 October 2026): hybrid. The gate (`swift-format`, `build-and-archive`) runs on Jose's Mac (runner `jose-mac-nook`, `~/actions-runner-nook`) while the repository variable `MACOS_RUNNER` is `["self-hosted","macOS","ARM64","nook"]`. The UI test parts (`ui-tests`, `ui-ipad`) run on GitHub's hosted `xcode-27` image, four at once, unless the variable `MACOS_UI_RUNNER` names the Mac (it is unset; measured: one Mac runner takes 54 min for a full UI batch, four hosted VMs 34). At about 99% done, run `gh variable delete MACOS_RUNNER` to go fully hosted; no file changes. `pause.sh` and `resume.sh` in the runner folder stop and start it. Each job there makes and deletes its own `nook-ci-` simulator (never touch other simulators), and fork pull requests never reach it. Details under CI in `README.md`.
- Milestone promotions to `main` (end of Phase 3, before 18, after 21, after 30, release): open the PR with `scripts/promote.sh`, not from `develop` directly. Squash-only merging means `main` and `develop` share no history after the first promotion, so a PR from `develop` would conflict. The script explains why. The PR body walks the security review gate in `closet/SECURITY_STANDARD.md` §11.
