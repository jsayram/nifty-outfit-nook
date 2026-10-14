# Nifty Outfit Nook

A native iOS app (SwiftUI) that styles outfits from the clothes you already own.

This repo holds the shipping app (the Xcode project, Swift packages, tests and CI) and the app's website in `website/`. Planning, the product requirements, design mockups and the security standard live in the separate `closet` repo:

- Build plan: `closet/SWIFT_BUILD_PLAN.md`
- Security standard (required): `closet/SECURITY_STANDARD.md`
- Product requirements: `closet/Nifty_Outfit_Nook_PRD_v2.md`

## Requirements

- Xcode 26.6 or later (Swift 6.3), with an iOS 26 simulator installed.
- Nothing else to install. The app has no third-party dependencies, and swift-format ships with Xcode. The tests use one test-only package, `swift-snapshot-testing`, which Xcode fetches on first build (see `docs/decisions/0002-snapshot-testing.md`).

## Open, build and run

Open `NiftyOutfitNook.xcodeproj` in Xcode, pick the `NiftyOutfitNook` scheme and an iPhone or iPad simulator, and run. The app's display name is "Outfit Nook".

Simulator builds need no signing setup. To run on a device, copy `Configs/Signing.local.xcconfig.example` to `Configs/Signing.local.xcconfig` and set your `DEVELOPMENT_TEAM`. That file is ignored by git, so no team ID is ever committed.

From the command line:

```sh
scripts/build.sh            # Debug build for the simulator
scripts/build.sh Release    # Release build
scripts/test.sh             # package tests, snapshot tests and UI tests on an iPhone simulator
scripts/check-release.sh    # after a Release build: no catalog or snapshot-testing code in the app
scripts/check-package-pins.sh  # the two Package.resolved files agree
scripts/format.sh           # swift-format lint (fails on any finding)
scripts/format.sh --fix     # rewrite files, then lint
scripts/install-hooks.sh    # once per clone: the gitleaks pre-commit hook
scripts/promote.sh "<title>" <body-file>  # at a milestone: open the develop-to-main promotion PR
```

The pre-commit hook needs gitleaks (`brew install gitleaks`). It stops any commit whose staged changes look like they contain a secret.

`scripts/test.sh` uses the iOS 26.5 runtime and prefers an iPhone 17 (see `scripts/simulator.sh`). The runtime is pinned because the snapshot references were recorded on it. Override with `NOOK_SIM_OS=27`, `NOOK_SIM_NAME="iPhone Air"` or `NOOK_SIM_ID=<udid>`, but expect snapshot failures on another runtime. Results land in `build/TestResults.xcresult`. Snapshot tests are explained in `Packages/NookKit/Sources/DesignSystem/README.md`.

The NookKit package targets iOS only, so `swift test` on the Mac doesn't work. Its tests run through the app scheme's test plan (`NiftyOutfitNook.xctestplan`) on a simulator.

Warnings are errors in every target: `SWIFT_TREAT_WARNINGS_AS_ERRORS` in `Configs/Base.xcconfig` for the app and UI tests, and `.treatAllWarnings(as: .error)` in `Package.swift` for NookKit.

## Component catalog

Debug builds launched with `-catalog` open a catalog of every DesignSystem component instead of the app, with switches for light, dark and text size. It's compiled only in Debug; `scripts/check-release.sh` checks that a Release build doesn't contain it.

## Sample data

Stage A runs on sample data only. Launch with `-fixtures demo`, `-fixtures empty` or `-fixtures large` to pick a set (the scheme passes `-fixtures demo`). Add options after colons, in any order:

- a behaviour for loading, error and offline states: `slow`, `offline`, `stylist-fails`, `stylist-partial` or `stores-fail`, for example `-fixtures demo:offline`;
- `weather=` with `sun`, `cloudy`, `rain`, `snow`, `night` or `unavailable`, to force the weather (and the Home window);
- `laundry=` with `off`, `clean`, `some` (2 dirty) or `full` (8 dirty), to force laundry tracking and the hamper.

For example `-fixtures demo:weather=snow:laundry=full`. Missing or unknown values fall back to `demo`, `normal` and the set's own weather (rain) and laundry.

The models, the store protocols and the fixture sets are described in `docs/models.md`.

## Folder structure

```
NiftyOutfitNook.xcodeproj    Thin app project. Folders are synchronized, so adding a file never edits it.
NiftyOutfitNook.xctestplan   Runs the NookKit tests and the UI tests.
NiftyOutfitNook/             App target: entry point, assets, entitlements, privacy manifest.
NiftyOutfitNookUITests/      XCUITest UI tests.
Packages/NookKit/            Almost all of the code.
  Sources/DesignSystem/      Tokens, shared components and the debug-only catalog (Phase 2).
  Sources/Models/            Domain types, rules as pure functions, and service protocols (Phase 3).
  Sources/Fixtures/          In-memory stores, the mock stylist, sample data sets and the -fixtures argument.
  Sources/Features/          Screens and view models, one folder per feature.
    Resources/               Localizable.xcstrings, the String Catalog for user-facing text.
  Tests/                     One Swift Testing target per module.
Configs/                     Build settings as xcconfig files.
  Base.xcconfig              Shared settings (iOS 26.0, Swift 6, strict concurrency).
  Debug.xcconfig             Debug configuration, Dev environment.
  Release.xcconfig           Release configuration, Production environment.
  App.xcconfig               App target: bundle ID, Info.plist keys, entitlements.
  UITests.xcconfig           UI test target.
  Environments/              Dev, Staging and Production. Non-secret settings only.
scripts/                     build.sh, test.sh, format.sh, simulator.sh, check-release.sh, check-package-pins.sh,
                             install-hooks.sh, merge-pr.sh, promote.sh.
.githooks/                   The gitleaks pre-commit hook.
.github/                     CI workflow, Dependabot, CODEOWNERS and the PR template.
docs/decisions/              Technical decision notes.
docs/models.md               The models, rules, store protocols and fixture sets.
website/                     The app's static website.
```

Features depend on DesignSystem and Models. Fixtures depends on Models. The app target links Features, Fixtures and DesignSystem (for the debug catalog) and only wires them together.

The local package is added to the project as a folder reference rather than a package reference. That keeps it editable in Xcode, lets the test plan run its test targets, and stops Xcode building it with warnings suppressed.

## Security defaults

- No App Transport Security exceptions. The generated Info.plist has no `NSAppTransportSecurity` keys.
- Data Protection is `NSFileProtectionComplete` through the `com.apple.developer.default-data-protection` entitlement.
- `PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, no collected data and no required-reason APIs. It's updated whenever that changes.
- No secrets anywhere. `Secrets.xcconfig` and `*.local.xcconfig` are ignored by git and only ever hold non-secret identifiers such as a team ID.

## Branches

Git Flow. `main` is what's released, `develop` is the integration branch, and every phase is a `feature/*` branch off `develop`. Releases go through `release/*`, urgent fixes through `hotfix/*`. Nothing is pushed straight to `main` or `develop`.

Rulesets on `main` and `develop` enforce this for everyone, administrators included: changes arrive by pull request, CI must pass, history stays linear and signed, and force pushes and deletion are blocked. Pull requests are squash-merged.

## CI

GitHub Actions runs `.github/workflows/ci.yml` on every pull request and on pushes to `develop` and `main`. Its three checks are all required:

- `swift-format`: `scripts/format.sh` on a `macos-26` runner.
- `build-and-test`: checks the two `Package.resolved` files agree, makes a Release build and checks it has no debug or test code, then runs `scripts/test.sh` with Xcode 26.6 on the iOS 26.5 simulator. Builds only use the versions in `Package.resolved`. A failed run uploads the test results and any failed snapshots.
- `gitleaks`: a scan of the full git history, using a pinned gitleaks release checked against its SHA-256.

Actions are pinned to full commit SHAs and the workflow token is read-only. Dependabot keeps the pins current.

## Repo settings

These live in GitHub's settings rather than in files, so they're listed here. All were set in Phase 1b.

- Ruleset "Protect main and develop", with no bypass actors: pull request required (squash only, no approvals needed while there's one maintainer), the three CI checks required from GitHub Actions, signed commits, linear history, and no force pushes or deletion.
- Merging: squash only, and branches are deleted after merge.
- Secret scanning with push protection, Dependabot alerts and security updates, and private vulnerability reporting.
- Actions: the default `GITHUB_TOKEN` is read-only and can't approve pull requests; only GitHub-owned actions are allowed, and they must be pinned to a full commit SHA; workflows from every outside contributor wait for approval.

## Reporting a security problem

See [SECURITY.md](SECURITY.md).

## License

Copyright © 2026 Jose Ramirez-Villa. All rights reserved. No license is granted to use, copy, modify or distribute this code.
