# Nifty Outfit Nook

A native iOS app (SwiftUI) that styles outfits from the clothes you already own.

This repo holds the shipping app (the Xcode project, Swift packages, tests and CI) and the app's website in `website/`. Planning, the product requirements, design mockups and the security standard live in the separate `closet` repo:

- Build plan: `closet/SWIFT_BUILD_PLAN.md`
- Security standard (required): `closet/SECURITY_STANDARD.md`
- Product requirements: `closet/Nifty_Outfit_Nook_PRD_v2.md`

## Requirements

- Xcode 27.1 or later (Swift 6.4), with the iOS 27.0 simulator runtime installed (the app still targets iOS 26.0). Tests run on iOS 27.0 because it's the only runtime on GitHub's `xcode-27` runners.
- Nothing else to install. The app has no third-party dependencies, and swift-format ships with Xcode. The tests use one test-only package, `swift-snapshot-testing`, which Xcode fetches on first build (see `docs/decisions/0002-snapshot-testing.md`).

## Open, build and run

Open `NiftyOutfitNook.xcodeproj` in Xcode, pick the `NiftyOutfitNook` scheme and an iPhone or iPad simulator, and run. The app's display name is "Outfit Nook".

Simulator builds need no signing setup. To run on a device, copy `Configs/Signing.local.xcconfig.example` to `Configs/Signing.local.xcconfig` and set your `DEVELOPMENT_TEAM`. That file is ignored by git, so no team ID is ever committed.

From the command line:

```sh
scripts/build.sh            # Debug build for the simulator
scripts/build.sh Release    # Release build
scripts/test.sh             # package tests, snapshot tests and UI tests on an iPhone simulator
scripts/test.sh -only-testing:NiftyOutfitNookUITests/HomeTests  # or any xcodebuild test selection
NOOK_TEST_PLAN=UITests scripts/test.sh -only-testing:NiftyOutfitNookUITests/HomeTests  # UI tests only, without building the package tests
scripts/check-release.sh    # after a Release build: no catalog, snapshot-testing code, sample data or debug flags in the app
scripts/check-package-pins.sh  # the two Package.resolved files agree
scripts/format.sh           # swift-format lint (fails on any finding), then check-strings.py and check-ui-taps.sh
scripts/check-strings.py    # fails on a String Catalog key no Swift file uses any more
scripts/check-ui-taps.sh    # fails on a UI test tap that doesn't wait for its effect (see UITestSupport.swift)
scripts/format.sh --fix     # rewrite files, then lint
scripts/install-hooks.sh    # once per clone: the gitleaks pre-commit hook
scripts/promote.sh "<title>" <body-file>  # at a milestone: open the develop-to-main promotion PR
scripts/bump-build.sh       # before an archive: set the build number (UTC date and time, ignored by git)
scripts/check-archive.sh    # unsigned Release archive for a device, and checks on what would be uploaded
```

The pre-commit hook needs gitleaks (`brew install gitleaks`). It stops any commit whose staged changes look like they contain a secret.

On CI (when `CI` is set), `scripts/test.sh` tells the tests so the large-closet speed checks allow three times their local bound. Each speed check also takes the fastest of three runs, so a stall from tests running in parallel doesn't fail it.

`scripts/test.sh` uses the iOS 27.0 runtime and prefers an iPhone 17 (see `scripts/simulator.sh`). `NOOK_SIM_FAMILY=iPad` picks an iPad (the iPad Pro 11-inch (M5) if there is one) for the iPad UI tests, `IPadTests`, `IPadStyleMeAndSavedTests` and `IPadKeyboardTests`, which skip themselves on an iPhone (`docs/ipad.md`). The runtime is pinned because the snapshot references were recorded on it. Override with `NOOK_SIM_OS=26.5`, `NOOK_SIM_NAME="iPhone Air"` or `NOOK_SIM_ID=<udid>`, but expect snapshot failures on another runtime. Results land in `build/TestResults.xcresult`. Snapshot tests are explained in `Packages/NookKit/Sources/DesignSystem/README.md`.

The NookKit package targets iOS only, so `swift test` on the Mac doesn't work. Its tests run through the app scheme's test plan (`NiftyOutfitNook.xctestplan`) on a simulator. The scheme has a second plan, `UITests.xctestplan`, with only the UI tests, so a UI-only run doesn't build the package test targets.

Warnings are errors in every target: `SWIFT_TREAT_WARNINGS_AS_ERRORS` in `Configs/Base.xcconfig` for the app and UI tests, and `.treatAllWarnings(as: .error)` in `Package.swift` for NookKit.

## Component catalog

Debug builds launched with `-catalog` open a catalog of every DesignSystem component instead of the app, with switches for light, dark and text size. Its last page shows look bundles (Phase 9, `docs/look-bundles.md`), which Features adds through `NookCatalogView(extraPages:)`. Add `-catalog-page <id>` to show one page alone (`search`, `sheet`, `toast`, `lookBundles` and so on), which the UI tests use instead of scrolling the whole catalog. It's compiled only in Debug; `scripts/check-release.sh` checks that a Release build doesn't contain it.

## Onboarding

A fresh install opens on the welcome, then four short steps (a name for the sign, where her things stay, her usual fit, and a sample or empty starting closet), then Home with its quick tour (Phase 17, `docs/onboarding.md`). Delete my data goes back to the welcome. Debug builds take `-onboarding reset` to show onboarding again and `-onboarding skip` to open Home on the `-fixtures` set for one launch, which every UI test but the onboarding ones passes.

## Quick tours

Each screen's quick tour starts the first time the screen shows (Phases 16a and 16b, `docs/tours.md`), and App tours on Profile replays any of them. Since Phase 17 the tours seen and the "Show tips on new screens" switch are kept across launches (with the onboarding state, see below). Debug builds take `-tour home` (or any tour's ID, such as `closet`) to start that tour whatever is recorded, `-tour reset` to forget the tours seen, and `-tour off` to stop tours starting by themselves, which the UI tests use. Both write to the kept state, so `-tour off` stays until a later `-tour reset` or Delete my data. Values combine with commas: `-tour reset,home`.

Two more debug-only flags are there for the UI tests: `-animations off` turns UIKit's animations off, so pushes, sheets and alerts appear at once (most UI tests pass it; the tour, onboarding and iPad tests don't), and `-toasts-stay` keeps toasts up ten times longer, so the Undo test can reach Undo on a slow CI runner. `scripts/check-release.sh` checks neither is in a Release build.

## Cutout benchmark

Debug builds launched with `-cutout-bench` open the cutout benchmark (Phase 8a) instead of the app: pick photos with the system picker (no photo-library permission needed) or use drawn samples, and it times each cutout, samples memory, shows the quality signals and exports the numbers as text. Since Phase 8b it also shows each photo as a sticker and as a tile, marking the one the signals pick. The simulator can't run Vision's subject lifting, so it needs a device. `docs/cutout-feasibility.md` has the steps and the go/no-go limits. Like the catalog, it's compiled only in Debug.

## TestFlight

Lily's builds go out through TestFlight as internal-only builds with sample data (Phase 18). `docs/testflight.md` has Jose's steps: the App ID and app record, adding Lily as a tester, archiving and uploading, the What to Test text, and how her notes come back. The version is 0.1.0 (`Configs/Version.xcconfig`), and `scripts/bump-build.sh` sets the build number before each archive. The app icon is a placeholder (`art/app-icon/README.md`).

## Sample data

Debug builds run on sample data, in memory. Since Phase 20a, Release builds have none: the sample sets and the `-fixtures` argument are compiled only in Debug, Release starts on an empty closet (onboarding has no closet step there), and `scripts/check-release.sh` checks it. Stage A runs on sample data only, in memory: whatever she adds or changes is gone when the app closes. The only things kept across launches are in the app's own `UserDefaults` suite: that onboarding is done, which starting closet she chose, the tours seen and the tips switch, and (since the Stage A audit) the name on her sign and her Style Me settings (Preferences, Avoid repeating outfits for, Track laundry). See `docs/onboarding.md`. Launch with `-fixtures demo`, `-fixtures empty` or `-fixtures large` to pick a set (the scheme passes `-fixtures demo`). Add options after colons, in any order:

- a behaviour for loading, error and offline states: `slow`, `offline`, `offline-once`, `stylist-fails`, `stylist-partial`, `stylist-insufficient`, `stylist-waits`, `stores-fail`, `photo-fails` or `picture-fails`, for example `-fixtures demo:offline`. Your looks' states use the stylist ones (`docs/your-looks.md`);
- `weather=` with `sun`, `cloudy`, `rain`, `snow`, `night` or `unavailable`, to force the weather (and the Home window);
- `laundry=` with `off`, `clean`, `some` (2 dirty) or `full` (8 dirty), to force laundry tracking and the hamper;
- `draft=` with `add`, `edit` or `look`, to start with an unsaved Add a piece, Edit or Make your own look draft, as if the app had been closed mid-way;
- `photos=` with `real` (the default), `drawn` or `samples`. `real` gives every piece that has a photo the AI-generated sample photo or its cutout (see below); `drawn` shows the drawings as before; `samples` is `real` plus eight pieces with drawn sample photos and stand-in cutouts, six shown as stickers and two as photo tiles (Phase 8b, `docs/stickers.md`);
- `wardrobe=full`, to add 30 more pieces with real photos to the demo set, one or more of every kind of piece, and two more saved looks with their try-on previews. The default is the demo closet's 21 pieces. It does nothing on the empty and large sets;
- `source=suitcase`, to start with her most recently used suitcase as Style Me's remembered source, on Home's suitcase and in Suitcases (Phase 13, `docs/suitcases-and-laundry.md`).

For example `-fixtures demo:weather=snow:laundry=full` or `-fixtures demo:wardrobe=full`.

The photos are real-looking sample images (AI-generated, no real people) bundled in `Packages/NookKit/Sources/Fixtures/Resources/SampleWardrobe`: a photo and a cutout for every demo piece except the old gray leggings, the 30 extras, the try-on photo and six try-on previews. They go through the same path real photos will (`Garment.photo`, `Garment.cutout`, `GarmentArtChoice`, the image loader), and the drawings stay as the fallback for a piece with no photo. The large set uses the same photos by kind and colour. The folder adds about 12.7 MB to the app. Release builds still carry it, unused, because SwiftPM copies a package's resources in every configuration (see `docs/decisions/0003-persistence-spike.md`). Its README says where the images came from and how `scripts/build-sample-wardrobe.swift` rebuilds them. Missing or unknown values fall back to `demo`, `normal`, the set's own weather (rain) and laundry, no draft and the main closet.

The models, the store protocols and the fixture sets are described in `docs/models.md`.

## Folder structure

```
NiftyOutfitNook.xcodeproj    Thin app project. Folders are synchronized, so adding a file never edits it.
NiftyOutfitNook.xctestplan   Runs the NookKit tests and the UI tests.
NiftyOutfitNook/             App target: entry point, app icon (AppIcon.icon), assets, entitlements, privacy manifest.
NiftyOutfitNookUITests/      XCUITest UI tests.
Packages/NookKit/            Almost all of the code.
  Sources/DesignSystem/      Tokens, shared components and the debug-only catalog (Phase 2).
  Sources/Models/            Domain types, rules as pure functions, and service protocols (Phase 3).
  Sources/Fixtures/          In-memory stores, the mock stylist, sample data sets and the -fixtures argument.
  Sources/Services/          Real services on Apple frameworks only. Phase 8a: subject lifting with Vision. Phase 17: the app
                             state kept in UserDefaults.
  Sources/Features/          Screens and view models, one folder per feature.
    Resources/               Localizable.xcstrings, the String Catalog for user-facing text.
  Tests/                     One Swift Testing target per module.
    PersistenceSpikeTests/   Phase 20a's persistence spike: SwiftData, migrations, files, export and sync. Never shipped.
Configs/                     Build settings as xcconfig files.
  Base.xcconfig              Shared settings (iOS 26.0, Swift 6, strict concurrency).
  Debug.xcconfig             Debug configuration, Dev environment.
  Release.xcconfig           Release configuration, Production environment.
  App.xcconfig               App target: bundle ID, Info.plist keys, entitlements.
  AppInfo.plist              The launch screen colour, merged into the generated Info.plist.
  Version.xcconfig           Version and build number (Phase 18).
  ExportOptions-TestFlight.plist  Upload options for a TestFlight Internal Only build.
  UITests.xcconfig           UI test target.
  Environments/              Dev, Staging and Production. Non-secret settings only.
scripts/                     build.sh, test.sh, format.sh, simulator.sh, check-release.sh, check-archive.sh,
                             check-package-pins.sh, check-ui-taps.sh, bump-build.sh, install-hooks.sh,
                             merge-pr.sh, promote.sh.
art/                         Sources for the room drawings (room/) and the app icon (app-icon/).
.githooks/                   The gitleaks pre-commit hook.
.github/                     CI workflow, Dependabot, CODEOWNERS and the PR template.
docs/decisions/              Technical decision notes. 0003 is the Phase 20a persistence spike, 0004 the backup and recovery design.
docs/models.md               The models, rules, store protocols and fixture sets.
docs/home-room.md            The Home room, its layouts and states.
docs/closet.md               Closet browsing: search, filters, the grid and garment pictures.
docs/garment-detail.md       Garment detail, Remove from closet and Recently deleted.
docs/add-a-piece.md          Add a piece and Edit, the form's checks, drafts and Describe in words.
docs/cutout-feasibility.md   Lifting garments out of photos: the pipeline, the benchmark and the go/no-go.
docs/stickers.md             Stickers and the photo tile: choosing, drawing, caching and the sample photos.
docs/look-bundles.md         Look bundles: the flat-lay layout, the view, the piece list and the idea tag.
docs/style-me.md             The Style Me request: the screen, its sheets and the checks.
docs/your-looks.md           Your looks: one outfit in three versions, the Saved tab, saving and every styling state.
docs/swap-and-editor.md      Swap a piece (ranking, See all, Remove and Undo) and Make your own look with its draft.
docs/saved-looks.md          Saved Looks: the grid, search and filters, look detail, and the Home shelf frames.
docs/try-on-pictures.md      Try it on, the Pictures tab, picture detail, and how pictures link to their looks.
docs/suitcases-and-laundry.md  Suitcases, a suitcase and packing, Add to a suitcase, Laundry, and the remembered source.
docs/profile.md              Profile, Fit and measurements, the try-on photo sheet, and hiding sensitive screens.
docs/settings.md             Track laundry, Accessibility, Help, Send feedback, Privacy and terms, and Delete my data.
docs/tours.md                Quick tours: the tour system, every screen's tour, App tours, the -tour flag, VoiceOver and the tests.
docs/onboarding.md           Onboarding: the welcome and its steps, what's kept across launches, a relaunch, and the -onboarding flag.
docs/testflight.md           Lily's TestFlight build: setup, each build, What to Test, her notes, and the release checks.
docs/accessibility-audit.md  The accessibility audit on every main screen, what it excuses and why, and what still needs a device.
docs/ipad.md                 iPad: the tab bar at the bottom, the rooms, Closet's and Saved Looks' columns, two panes, readable widths, sheets and window sizes.
website/                     The app's static website.
```

Features depend on DesignSystem and Models. Fixtures and Services depend on Models. The app target links Features, Fixtures, DesignSystem (for the debug catalog) and Services (the app state kept in `UserDefaults`, and the debug cutout benchmark) and only wires them together.

The local package is added to the project as a folder reference rather than a package reference. That keeps it editable in Xcode, lets the test plan run its test targets, and stops Xcode building it with warnings suppressed.

## Security defaults

- No App Transport Security exceptions. The generated Info.plist has no `NSAppTransportSecurity` keys.
- Data Protection is `NSFileProtectionComplete` through the `com.apple.developer.default-data-protection` entitlement.
- `PrivacyInfo.xcprivacy` declares no tracking, no tracking domains and no collected data. Its one required-reason API is `UserDefaults` (reason `CA92.1`, data only this app reads), since Phase 17 keeps the onboarding and tour flags there, and the Stage A audit the sign name and Style Me settings. It's updated whenever that changes.
- No secrets anywhere. `Secrets.xcconfig` and `*.local.xcconfig` are ignored by git and only ever hold non-secret identifiers such as a team ID.

## Branches

Git Flow. `main` is what's released, `develop` is the integration branch, and every phase is a `feature/*` branch off `develop`. Releases go through `release/*`, urgent fixes through `hotfix/*`. Nothing is pushed straight to `main` or `develop`.

Rulesets on `main` and `develop` enforce this for everyone, administrators included: changes arrive by pull request, CI must pass, history stays linear and signed, and force pushes and deletion are blocked. Pull requests are squash-merged.

## CI

GitHub Actions runs `.github/workflows/ci.yml` on every pull request and on pushes to `develop` and `main`. Its three checks are all required:

- `swift-format`: `scripts/format.sh` on an `xcode-27` runner.
- `build-and-test`: passes only when these parallel jobs all pass, all with Xcode 27.1:
  - `build-and-archive` checks the two `Package.resolved` files agree, builds for testing (the UI test plan, then the full plan) and uploads what it built as artifacts of the run, makes an unsigned Release archive for a real iPhone and checks what would ship (`scripts/check-archive.sh`, which also runs `scripts/check-release.sh` on the device binary), then runs `CatalogTests`, `ProfileTests` and `CutoutBenchTests`;
  - `ui-tests (ui-home-and-settings)`, `(ui-add-and-tours)` and `(ui-rest)` run the other phone UI tests in three parts, by test class, and `ui-tests (ui-ipad)` runs the iPad UI tests on an iPad simulator, then every package test target. These start with `build-and-archive`, boot their simulator while it builds, then download its build (`scripts/wait-for-artifact.sh`, this run's artifacts only) and test without building. `ui-rest` is every UI test class the others don't name, so a new class is never skipped (a new iPad class goes in `ui-ipad`). The workflow lists each part's classes with their CI times; move a class when one part grows well past the others. The free plan runs five macOS jobs at once, so there are five, balanced to about the same length.

  A pull request that only changes docs (Markdown files outside the source folders, `docs/`, `website/`) skips those jobs, and `build-and-test` passes without them. The small `changes` job decides, from the files the pull request changes. Pushes to `develop` and `main` always run everything.

  Tests run through `scripts/test.sh` on the iOS 27.0 simulator. A failed UI test runs once more on CI only (`-retry-tests-on-failure -test-iterations 2`), because the hosted simulator sometimes fails to launch the app; a test that fails twice still fails the job. The UI tests' shared waits are in `NiftyOutfitNookUITests/UITestSupport.swift`. Builds only use the versions in `Package.resolved`. A failed test job uploads its test results and any failed snapshots. Nothing is cached between runs, so a pull request can't leave build output for a later run to pick up.

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
