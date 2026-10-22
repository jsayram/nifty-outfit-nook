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

`scripts/test.sh` uses the iOS 27.0 runtime and prefers an iPhone 17 (see `scripts/simulator.sh`). `NOOK_SIM_FAMILY=iPad` picks an iPad (the iPad Pro 11-inch (M5) if there is one) for the iPad UI tests (paused; see "CI"), `IPadTests`, `IPadStyleMeAndSavedTests` and `IPadKeyboardTests`, which skip themselves on an iPhone (`docs/ipad.md`). The runtime is pinned because the snapshot references were recorded on it. Override with `NOOK_SIM_OS=26.5`, `NOOK_SIM_NAME="iPhone Air"` or `NOOK_SIM_ID=<udid>`, but expect snapshot failures on another runtime. Results land in `build/TestResults.xcresult`. Snapshot tests are explained in `Packages/NookKit/Sources/DesignSystem/README.md`.

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

Debug builds run on sample data, in memory. Since Phase 20a, Release builds have none: the sample sets and the `-fixtures` argument are compiled only in Debug, Release starts on an empty closet (onboarding has no closet step there), and `scripts/check-release.sh` checks it.

Since Phase 21a her own closet is kept in a SwiftData store on the iPhone (`Application Support/Store`, Data Protection `complete`): everything she adds or changes, her profile, drafts and the unsent feedback note, with the onboarding state and the tours seen. That's every Release build, and a Debug build on the empty closet. The debug sample closet stays in memory and comes back as it ships at each launch, keeping only the name on her sign and her Style Me settings, so `-fixtures` and its options work as before. `-onboarding skip` keeps nothing, and `-onboarding reset` also erases her data in the store. The first launch of a 21a build moves Stage A's `UserDefaults` suite into the store. See `docs/models.md` (Real storage) and `docs/onboarding.md`. Launch with `-fixtures demo`, `-fixtures empty` or `-fixtures large` to pick a set (the scheme passes `-fixtures demo`). Add options after colons, in any order:

- a behaviour for loading, error and offline states: `slow`, `offline`, `offline-once`, `stylist-fails`, `stylist-partial`, `stylist-insufficient`, `stylist-waits`, `stores-fail`, `photo-fails` or `picture-fails`, for example `-fixtures demo:offline`. Your looks' states use the stylist ones (`docs/your-looks.md`);
- `weather=` with `sun`, `cloudy`, `rain`, `snow`, `night` or `unavailable`, to force the weather (and the Home window);
- `laundry=` with `off`, `clean`, `some` (2 dirty) or `full` (8 dirty), to force laundry tracking and the hamper;
- `draft=` with `add`, `edit` or `look`, to start with an unsaved Add a piece, Edit or Make your own look draft, as if the app had been closed mid-way;
- `photos=` with `real` (the default), `drawn` or `samples`. `real` gives every piece that has a photo the AI-generated sample photo or its cutout (see below); `drawn` shows the drawings as before; `samples` is `real` plus eight pieces with drawn sample photos and stand-in cutouts, six shown as stickers and two as photo tiles (Phase 8b, `docs/stickers.md`);
- `wardrobe=full`, to add 30 more pieces with real photos to the demo set, one or more of every kind of piece, and two more saved looks with their try-on previews. The default is the demo closet's 21 pieces. It does nothing on the empty and large sets;
- `source=suitcase`, to start with her most recently used suitcase as Style Me's remembered source, on Home's suitcase and in Suitcases (Phase 13, `docs/suitcases-and-laundry.md`).

For example `-fixtures demo:weather=snow:laundry=full` or `-fixtures demo:wardrobe=full`.

The photos are real-looking sample images (AI-generated, no real people) kept in `Packages/NookKit/Tests/NookTestSupport/SampleWardrobe` (the one copy): a photo and a cutout for every demo piece except the old gray leggings, the 30 extras, the try-on photo and six try-on previews. They go through the same path real photos will (`Garment.photo`, `Garment.cutout`, `GarmentArtChoice`, the image loader), and the drawings stay as the fallback for a piece with no photo. The large set uses the same photos by kind and colour. The folder adds about 12.7 MB to a Debug build. Release, TestFlight and App Store builds never carry it: the app project copies the folder in, `Configs/Release.xcconfig` leaves it out, the package tests read it from `NookTestSupport`, and `scripts/check-release.sh` fails if any sample photo is in a built Release app. Its README says where the images came from and how `scripts/build-sample-wardrobe.swift` rebuilds them. Missing or unknown values fall back to `demo`, `normal`, the set's own weather (rain) and laundry, no draft and the main closet.

The models, the store protocols and the fixture sets are described in `docs/models.md`.

## Folder structure

```
NiftyOutfitNook.xcodeproj    Thin app project. Folders are synchronized, so adding a file never edits it.
NiftyOutfitNook.xctestplan   Runs the NookKit tests, the hosted unit tests and the UI tests.
NiftyOutfitNook/             App target: entry point, app icon (AppIcon.icon), assets, entitlements, privacy manifest.
NiftyOutfitNookUITests/      XCUITest UI tests.
NiftyOutfitNookTests/        Unit tests hosted in the app: StoreKit's test sessions and the local .storekit file (Phase 30a).
Packages/NookKit/            Almost all of the code.
  Sources/DesignSystem/      Tokens, shared components and the debug-only catalog (Phase 2).
  Sources/Models/            Domain types, rules as pure functions, and service protocols (Phase 3).
  Sources/Fixtures/          In-memory stores, the mock stylist, sample data sets and the -fixtures argument.
  Sources/Services/          Real services on Apple frameworks only. Phase 8a: subject lifting with Vision. Phase 21a: the
                             real store (Storage/: SwiftData, the migration coordinator, every store), and the
                             one-time move of Stage A's UserDefaults suite (AppState/).
  Sources/Features/          Screens and view models, one folder per feature.
    Resources/               Localizable.xcstrings, the String Catalog for user-facing text.
  Tests/                     One Swift Testing target per module.
    PersistenceSpikeTests/   Phase 20a's persistence spike: SwiftData, migrations, files, export and sync. Never shipped.
                             Phase 21a promoted the store, the stores and the migration coordinator into Services.
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
docs/payments.md             The styling subscription: StoreKit, access rules, the paywall, tests and App Store Connect setup.
docs/tours.md                Quick tours: the tour system, every screen's tour, App tours, the -tour flag, VoiceOver and the tests.
docs/onboarding.md           Onboarding: the welcome and its steps, what's kept across launches, a relaunch, and the -onboarding flag.
docs/testflight.md           Lily's TestFlight build: setup, each build, What to Test, her notes, and the release checks.
docs/accessibility-audit.md  The accessibility audit on every main screen, what it excuses and why, and what still needs a device.
docs/ipad.md                 iPad: the tab bar at the bottom, the rooms, Closet's and Saved Looks' columns, two panes, readable widths, sheets and window sizes.
website/                     The app's static website.
```

Features depend on DesignSystem and Models. Fixtures and Services depend on Models. The app target links Features, Fixtures, DesignSystem (for the debug catalog) and Services (the real store since Phase 21a, and the debug cutout benchmark) and only wires them together.

The local package is added to the project as a folder reference rather than a package reference. That keeps it editable in Xcode, lets the test plan run its test targets, and stops Xcode building it with warnings suppressed.

## Security defaults

- No App Transport Security exceptions. The generated Info.plist has no `NSAppTransportSecurity` keys.
- Data Protection is `NSFileProtectionComplete` through the `com.apple.developer.default-data-protection` entitlement.
- `PrivacyInfo.xcprivacy` declares no tracking, no tracking domains and no collected data. Its required-reason APIs are `UserDefaults` (reason `CA92.1`, data only this app reads: Phase 17 kept the onboarding and tour flags there, and since 21a the app reads them once to move them into the store) and, since Phase 21a, disk space (reason `E174.1`: the migration checks there's room for its safety copy before it starts). It's updated whenever that changes. `scripts/check-archive.sh` checks it.
- No secrets anywhere. `Secrets.xcconfig` and `*.local.xcconfig` are ignored by git and only ever hold non-secret identifiers such as a team ID.

## Branches

Git Flow. `main` is what's released, `develop` is the integration branch, and every phase is a `feature/*` branch off `develop`. Releases go through `release/*`, urgent fixes through `hotfix/*`. Nothing is pushed straight to `main` or `develop`.

Rulesets on `main` and `develop` enforce this for everyone, administrators included: changes arrive by pull request, CI must pass, history stays linear and signed, and force pushes and deletion are blocked. Pull requests are squash-merged.

## CI

GitHub Actions runs `.github/workflows/ci.yml` on every pull request and on pushes to `develop` and `main`, and by hand for the batch UI run. Its three checks are all required.

**What runs when** (since 22 October 2026):

| Trigger | What runs |
|---|---|
| Pull request (the fast gate) | `swift-format`, `gitleaks`, the build and archive check, and every package test, iPhone snapshot tests included |
| Pull request with the `run-ui` label | The fast gate plus the UI tests (the three iPhone parts) |
| Push to `develop` or `main` | The fast gate again. No UI tests. |
| Manual run on `develop`, the batch (`scripts/run-ui-batch.sh`) | The fast gate plus the whole UI suite on an iPhone simulator |

The UI tests never start by themselves. A pull request that touches UI paths still gets the fast gate only, and a note in the run's summary says its UI tests are due. Run a batch after about every three UI-touching merges and at phase milestones: `scripts/run-ui-batch.sh` starts the manual run on the tip of `develop` and prints the run's URL (`gh run watch <id> --exit-status --interval 60` waits for it). If a batch fails, bisect the commits since the last green batch. Put the `run-ui` label on a pull request that needs its UI tests before it merges.

**iPad testing is paused** until the app's features are done. The iPhone 12 is Lily's phone and the main target, and the iPad comes at the end, as UI work. Nothing was deleted:
- The `ui-ipad` job (the iPad UI tests, on an iPad simulator) runs only on a manual run with `include_ipad` ticked. `scripts/run-ui-batch.sh --ipad` does that.
- The iPad snapshot test cases in the package tests (the `*IPadSnapshotTests` suites, `piecesIPad`, the iPad tour and onboarding cases, the iPad component pages) skip themselves unless `NOOK_IPAD_SNAPSHOTS=1`. They draw iPad-sized windows with `ImageRenderer`, so they run on any simulator, and the package tests run on an iPhone simulator in CI. Their reference images are still in `__Snapshots__`.
- The iPad layout logic tests (`WindowLayoutTests`, `RoomLayoutTests`, `RoomPlanTests`) are plain arithmetic and still run on every pull request.

**Turning iPad testing back on:**
1. In `.github/workflows/ci.yml`, change the `ui-ipad` job's `if` to `needs.changes.outputs.ui == 'true'` (it then runs whenever the UI tests do), and change `NOOK_IPAD_SNAPSHOTS` in the package test step to `'1'` (the iPad snapshots then run in every package test run, and the iPad reference images get checked on each PR again). Keep `ui-ipad` in the `build-and-test` aggregator as it is. The `include_ipad` input and the `ipad` output of `changes` can go.
2. Locally: `NOOK_IPAD_SNAPSHOTS=1 scripts/test.sh` for the snapshots, `NOOK_SIM_FAMILY=iPad scripts/test.sh -only-testing:NiftyOutfitNookUITests/IPadTests` for the UI tests. In Xcode, add `NOOK_IPAD_SNAPSHOTS` = `1` to the scheme's test environment variables.
3. Remove this paragraph's "paused" wording here and in `AGENTS.md`.

**Which runner the macOS jobs use** (since 22 October 2026). During development the gate runs on a self-hosted runner on Jose's Mac, which is faster than GitHub's hosted one, and the UI test parts run on GitHub's hosted `xcode-27` image, four at once. At about 99% done, switch everything back to hosted. Two repository variables hold JSON values that the workflow reads as `runs-on`:

| Variable | Jobs | Today |
|---|---|---|
| `MACOS_RUNNER` | `swift-format`, `build-and-archive` (the build, the archive check, the package tests) | `["self-hosted","macOS","ARM64","nook"]`, the runner `jose-mac-nook` |
| `MACOS_UI_RUNNER` | `ui-tests` (every iPhone part) and `ui-ipad` | unset, so GitHub's hosted `xcode-27` image |

Unset, empty or `"xcode-27"` means hosted. The reason for the split is measured (pull request #87): the Mac is faster per job (the gate 3.9 min against 16.5), but it runs one job at a time, so a full UI batch took 54 min there against 33.8 min on four hosted VMs.

- **Switch the gate to hosted:** `gh variable delete MACOS_RUNNER`. **Back to the Mac:** `gh variable set MACOS_RUNNER --body '["self-hosted","macOS","ARM64","nook"]'`. **UI parts on the Mac:** `gh variable set MACOS_UI_RUNNER --body '["self-hosted","macOS","ARM64","nook"]'`; back to hosted with `gh variable delete MACOS_UI_RUNNER`. No file changes either way.
- **The build for the hosted UI parts.** `build-and-archive` builds the UI test plan first and uploads it (`ui-test-products`, 28 MB), and the hosted parts download it, as when everything was hosted. The Mac's Xcode 27.1 and the hosted 27.1 make the same products. If the Mac is busy and `build-and-archive` hasn't started after 3 minutes, a hosted part builds for itself (about 4 minutes, measured 22 October 2026) rather than wait: the Mac uploads within a minute of starting, so 3 minutes of queue is about break-even. The queue is often the run that a merge just started, so a batch started right after a merge builds on the hosted parts. A part that does wait sees the upload step finish even if GitHub's artifact list trails it, and prints what it sees every minute.
- `changes`, `gitleaks` and `build-and-test` always run on `ubuntu-latest`. `swift-format` stays on the `MACOS_RUNNER` runner because `scripts/format.sh` uses Xcode's `swift-format`.
- **The runner** is GitHub's official runner (v2.338.0), installed in `~/actions-runner-nook` as a launchd service that starts at login. Its labels are `self-hosted`, `macOS`, `ARM64` and `nook`. `~/actions-runner-nook/pause.sh` stops it and `resume.sh` starts it again. While it is stopped, macOS jobs wait in the queue (GitHub drops them after 24 hours), so for a long pause switch to hosted instead. Check it with `gh api repos/jsayram/nifty-outfit-nook/actions/runners`.
- **Stays awake.** The runner's job hooks (`~/actions-runner-nook/hooks/`) run the built-in `caffeinate` while a job runs and stop it after. No system setting is changed.
- **Forks never reach it.** A pull request from a fork gets the hosted runner (the `runs-on` line checks the head repository), a first step in every macOS job fails the job if it ever lands on the self-hosted runner anyway, and the repository setting for outside contributors' workflows is "Require approval for all external contributors". No secrets are passed to any job. Only branches in this repository, pushes and manual runs reach the runner.
- **Xcode.** `scripts/ci-select-xcode.sh` uses `XCODE_APP` (`/Applications/Xcode_27.1.app`, the hosted image) if it exists, and `/Applications/Xcode.app` otherwise (the Mac). It sets `DEVELOPER_DIR` and doesn't run `sudo xcode-select`.
- **Simulators.** Each self-hosted job makes its own simulator with `scripts/ci-simulator.sh` (named `nook-ci-<run>-<attempt>-<job>-<pid>`, on the iOS 27.0 runtime the snapshot references were recorded on; an iPhone 12, or an iPad Pro 11-inch (M5) for the iPad part) and deletes it in a last step that always runs. It never uses, shuts down or deletes any other simulator, and never downloads a runtime. A `nook-ci-` simulator left by a killed job is deleted by the next job's start.
- **StoreKit tests on the Mac only.** The StoreKit suites (`SubscriptionStoreKitTests` and the `CreditsStoreKitTests` nested in it, Phases 30a and 30b) skip themselves on CI, because StoreKit's test environment serves no products on the iOS 27.0 simulator (`NOOK_CI`). They pass on iOS 26.5. When `build-and-archive` runs on the self-hosted runner, a second step makes its own iPhone 12 simulator on iOS 26.5 (`NOOK_SIM_OS=26.5 scripts/ci-simulator.sh create iPhone`, named `nook-ci-...` like the first one, which it leaves alone), runs those suites on it with `NOOK_STOREKIT=1` (which switches the skip off) against the build the job already made, and deletes it in the job's last step, which always runs. On hosted runners they stay skipped. The step runs only when the `changes` job says it is due: the change touches StoreKit code, the hosted tests or this CI setup (see the `storekit` case in `ci.yml`), the pull request has the `run-storekit` label, or it is a manual run. It is advisory (`continue-on-error`, 6 minute limit) for now: on this Mac at a load average of 400 to 900, StoreKit's own daemon sometimes stops answering on a fresh simulator and a test sits until the suite's two-minute limit, in about half of about 15 local runs and in both runs in CI, and a hang adds up to 6 minutes. A failure shows as a warning on the run and keeps the result bundle; take `continue-on-error` off after a few clean runs in a row. The tests' own causes are fixed (`docs/payments.md`, Testing). One test is left out: `checkpointPurchaseRenewRestoreExpire`, which waits 95 seconds or more on StoreKit's sped-up clock and passed once in ten runs on this Mac at a load average of 500 to 900. The fast tests cover each of its parts. Run it with `scripts/test.sh -only-testing:NiftyOutfitNookTests/SubscriptionStoreKitTests/checkpointPurchaseRenewRestoreExpire()` on a quiet machine.
- **One job at a time.** The runner runs one job at a time. If `MACOS_UI_RUNNER` also names it, the self-hosted `ui-tests` parts don't wait for `build-and-archive` (they would hold the runner it needs). Each builds from the cached DerivedData instead, which is current after the first build, and the build artifacts are not uploaded. Parts on the hosted runners wait for the artifact and download it.
- **Caches.** `scripts/ci-local-cache.sh` links `build/DerivedData` (and with it the SwiftPM checkouts) to `~/actions-runner-nook/_work/_cache/DerivedData`, which survives between jobs. This is a trade-off against "nothing is cached between runs" below: on the self-hosted runner a branch's build output stays for later runs. Only this repository's own branches run there. To start cold, delete that folder or tick `cold_cache` on a manual run.
- **Timing, 22 October 2026:** the hosted-versus-local table is in pull request #87: the PR gate took about 16.5 min hosted and 3.9 min local (warm); a full iPhone UI batch took 33.8 min hosted (four jobs at once) and 54 min local (one job at a time, each job 2 to 3 times faster).

- `swift-format`: `scripts/format.sh` on the macOS runner.
- `build-and-test`: passes only when these jobs all pass, all with Xcode 27.1:
  - `build-and-archive` checks the two `Package.resolved` files agree, builds for testing, makes an unsigned Release archive for a real iPhone and checks what would ship (`scripts/check-archive.sh`, which also runs `scripts/check-release.sh` on the device binary), and runs every package test target on an iPhone simulator, iPhone snapshot tests included. This runs on every change except docs-only ones. When the UI tests run (see above) it also builds the UI test plan, uploads it, and runs `CatalogTests`, `ProfileTests` and `CutoutBenchTests`.
  - `ui-tests (ui-audit-and-settings)`, `(ui-large-text-and-add)`, `(ui-saved-tours-and-jobs)` and `(ui-rest)` run the UI tests, in parts by test class, **only with the `run-ui` label or on a manual run** (and `(ui-ipad)` too, on a manual run with `include_ipad`). On the hosted runners they start with `build-and-archive`, boot their simulator while it builds, then download its build (`scripts/wait-for-artifact.sh`, this run's artifacts only) and test without building. `ui-rest` is every UI test the others don't name, so a new class is never skipped (a new iPad class goes in `ui-ipad`). Each part has about 1250 seconds of tests, which is 25 minutes on an average hosted VM (a slow one takes up to 1.4 times as long) (the table is in `ci.yml`). Before 22 October 2026 there were three parts, and `ui-rest` ran out of its 40 minutes in two batches. The free plan runs five macOS jobs at once, so a run has at most five.

  The small `changes` job decides, from the files changed:
  - Docs only (Markdown outside the source folders, `docs/`, `website/`): no build or test jobs; `build-and-test` still passes.
  - **UI paths**, which make a change UI-touching (they no longer turn the UI test jobs on; the summary notes that the UI tests are due): view and screen files under `Packages/NookKit/Sources/Features/` (any file there except `*Model.swift`), everything under `Packages/NookKit/Sources/DesignSystem/` (components, colours, typography, asset catalogs), everything under `NiftyOutfitNook/` (the app file, `Assets.xcassets`, entitlements), `Configs/AppInfo.plist`, `NiftyOutfitNook.xcodeproj/`, any `*.xcstrings` or `*.xcassets`, and `NiftyOutfitNookUITests/`.
  - Everything else (models, services, fixtures, backup and storage code, package tests, `scripts/`, workflow files) builds, archives and runs the package tests too.
  - The UI jobs run only with the `run-ui` label on a non-docs pull request, or on a manual run. Otherwise they report as skipped, `build-and-test` accepts that, and they never block a merge.

  **Two tiers of UI tests.** A few UI tests skip themselves on CI (`NOOK_PR_RUN=1`, set by the workflow and passed on by `scripts/test.sh`) and run only in a manual full-suite run or locally. They are the large-text (AX5) audit sweep and the other AX5 checks, the two long tour walks (`ScreenToursTests`), the cutout benchmark, and tests whose behaviour package tests already cover (the fit-value sheet, the feedback share sheet, Your looks' forced states, the launch fixtures). Each such test starts with `try skipOnPullRequests("...")`, and its comment says what covers it. To run them locally, leave `NOOK_PR_RUN` unset.

  Tests run through `scripts/test.sh` on the iOS 27.0 simulator. A failed UI test runs once more on CI only (`-retry-tests-on-failure -test-iterations 2`), because the hosted simulator sometimes fails to launch the app; a test that fails twice still fails the job. On CI the script also turns off `xcodebuild`'s diagnostics collection after a failure, which waited 600 seconds on the hosted runner before it reported, and it starts a test run once more when the test runner never started at all (no test case ran, and `xcodebuild` reported a start-up error such as "Timed out waiting for AX loaded notification"). A run with any test case in its log is never started again this way. The UI tests' shared waits are in `NiftyOutfitNookUITests/UITestSupport.swift`. Builds only use the versions in `Package.resolved`. A failed test job uploads its test results and any failed snapshots. On the hosted runners nothing is cached between runs, so a pull request can't leave build output for a later run to pick up (the self-hosted runner caches DerivedData; see above).
  **A stalled notification service** (22 October 2026). On the iOS 27.0 simulator, while the host is under heavy load (a load average of 300 to 600 on Jose's Mac, with several simulators and CI jobs running), SpringBoard's notification server can be stuck for minutes waiting on a `dasd` that is blocked on its own XPC call (found with `sample`: `UNSUserNotificationServer init` inside `BGSystemTaskScheduler submitTaskRequest`), and a fresh simulator is the likeliest to be stuck. Until it is free, `UNUserNotificationCenter` doesn't answer in any app on that simulator. Two things follow. Your looks no longer waits for iOS's answer before showing looks (a test in `YourLooksCloudTests` covers it), and `BackgroundJobsTests` waits (up to 5 minutes) for the simulator's notification service to answer before its notification test starts, and skips with that reason if it never does. On a cold simulator the service can take minutes to come up while the host is busy. A simulator on iOS 26.5 doesn't do this (`NOOK_SIM_OS=26.5`), and the same suite passed on a warm simulator at a load of about 170 and below. The StoreKit suite (`SubscriptionStoreKitTests`) fails on the iOS 27.0 simulator on this Mac too, so that one is the simulator, not the hosted runner.

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
