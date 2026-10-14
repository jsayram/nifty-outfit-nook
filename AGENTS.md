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
- Work on `feature/<phase>-<name>` off `develop`. `main` and `develop` are protected: open a PR into `develop`, wait for CI (`gh pr checks --watch`), then `gh pr merge --squash --delete-branch`.
- Before a PR: `scripts/format.sh` and `scripts/test.sh` pass.
