# Onboarding

Phase 17, 16 October 2026. The first run: a welcome, four short steps, and Home with its quick tour. Spec: PRD §5.1 ("First launch"), the Onboarding row in PRD §7, §7.8 and FR-73 (Home's tour starts when onboarding finishes), AC-103, and `closet/DATA_MAP.md`. Visual reference: `onboarding.html` in `closet/prototypes/RoomDirectionMockups/screens`. The amendment has no items for Phase 17.

The welcome follows the mockup. The steps after it have no mockup; they follow the PRD's list (a name, the privacy explanation before any setup that matters, optional fit, no extra work) in the layout of Profile and the settings screens.

## What's where

| File | Holds |
|---|---|
| `Models/Onboarding/Onboarding.swift` | `StartingCloset`, `OnboardingState`, `OnboardingAnswers` and the `OnboardingStateStore` protocol |
| `Fixtures/Stores/InMemoryOnboardingStore.swift` | The store in memory, for tests and previews |
| `Services/AppState/AppStateDefaults.swift` | `DefaultsOnboardingStore`, `DefaultsTourProgressStore` and (since the Stage A audit) `DefaultsProfileSettingsKeeper`: what's kept across launches in the app's own `UserDefaults` suite |
| `Models/Profile/KeptProfileSettings.swift` | The name on the sign and the Style Me settings kept across launches, and `KeptSettingsProfileStore`, the profile store that keeps them (Stage A audit) |
| `Fixtures/FixtureServices.swift` | `make(_:startingCloset:tours:onboarding:)`: the sample data for the closet she chose |
| `Features/Shared/AppRootView.swift`, `AppRootModel.swift` | The root: onboarding or the tabs, finishing, a relaunch, Delete my data. `AppLaunch` is what the app target hands it |
| `Features/Onboarding/OnboardingFlow.swift` | The welcome and the steps in one navigation stack |
| `Features/Onboarding/WelcomeView.swift` | The welcome: the sky, the porch scene (`PorchScene`) and the buttons, laid out by `WelcomeStack` |
| `Features/Onboarding/OnboardingPage.swift` | A step's page: the wall with its title, "Step 1 of 4" and a drawing, the content, the buttons |
| `Features/Onboarding/OnboardingSteps.swift` | The four steps |
| `Features/Onboarding/OnboardingModel.swift`, `OnboardingText.swift` | Moving through the steps and their words |
| `Features/Onboarding/OnboardingLaunchOptions.swift` | The `-onboarding` debug flag |

## The flow

1. **Welcome** (`onboarding.html`). "Welcome home", "Style outfits from the clothes you already own. Your closet stays on this iPhone.", **Get started**, and the text button **I already use Nifty Outfit Nook**, which goes straight to Home with the sample closet and no name. No Welcome tour: the mockup's tour points at these two buttons, and the screen already says what they do.
2. **Your name** (step 1 of 4). One field, with the name sign on the wall showing what she types. The rules are Profile's (`NameRules.signName`). Optional: empty is fine and the sign says Hello. Continue, or Skip for now.
3. **Your closet stays here** (step 2). In plain words: what the app does; that her pieces, looks, name and fit stay on the iPhone with no account; that this test build sends nothing and asks for no camera, photos, location or notifications; that later features will say what they send and ask first. Then a note on what the test build keeps when it closes: "When this test build closes, it keeps your name and your Style Me settings in Profile, which closet you chose and which tips you've seen. It forgets the rest, like your fit and the pieces and looks you add." Continue only.
4. **How you like clothes to fit** (step 3). Fitted, Comfortable or Relaxed, as on Fit and measurements, none chosen to start. Measurements aren't asked for: they're optional and Sensitive, and FR-01 rules out extra mandatory onboarding. The note says where to change it and add them. Continue, or Skip for now.
5. **Choose a starting closet** (step 4). **Sample closet** (chosen to start) or **Empty closet**, each with what it means in this test build. The armoire on the wall fills or empties with the choice. **Go to my room** finishes.

Each step is pushed, with Back in the bar. Nothing is saved until Go to my room (or I already use). Then `AppRootModel.finish` builds the services for the chosen closet, writes the name and fit to its profile, keeps that onboarding is done, and opens the tabs. Home's tour starts at once, as on any first visit (PRD §7.8). If a save fails (`-fixtures demo:stores-fail`), onboarding stays and says "That didn't work. Try again."

Nothing in onboarding asks for a permission or makes an account.

## What's kept across launches

Stage A has no real storage: the closet, looks, profile and everything she types are in memory. 16b noted that this made every tour show again after each relaunch, which would make Lily's TestFlight build feel broken, and onboarding would show every time too. So a few flags are kept in a `UserDefaults` suite of the app's own, `com.jsayram.niftyoutfitnook.appstate`, and since the Stage A audit (16 October 2026) the name on her sign and her Style Me settings too:

| Key | Value |
|---|---|
| `onboarding.completed` | `true` once she finishes |
| `onboarding.startingCloset` | `sample` or `empty` |
| `tours.showsTips` | "Show tips on new screens", absent means on |
| `tours.seenVersions` | Each tour seen, by ID, with the content version seen |
| `profile.signName` | The first name on her sign, as saved (may be empty) |
| `profile.pieceMode` | Preferences: `mineAndOneIdea` or `onlyMine` |
| `profile.repeatWindow` | Avoid repeating outfits for: `oneWeek`, `twoWeeks` or `noLimit` |
| `profile.tracksLaundry` | The Track laundry switch |

`closet/DATA_MAP.md` (updated in this phase) puts the first four in the lowest tier: no name, nothing she typed, nothing about her body or closet, no dates and no identifier. They name only the app's own screens and settings. The rest of tour progress, how each tour ended and when, is Personal in the data map, so it stays in memory for the session (`TourProgress.records`); the rule that decides whether a tour starts only needs the seen version (`TourProgress.seenVersions`).

The name and the three settings are Personal. Jose decided in the Stage A audit that the test build keeps them, so a relaunch doesn't put Hello back on the sign or undo her settings; the data map has a row for each. Nothing else from the profile is written: her usual fit, measurements, fitting pieces and try-on photo are Sensitive and stay in memory, and so do the remembered source and occasion. `KeptSettingsProfileStore` sits in front of the in-memory profile store: it starts from the launch's profile with the kept values put in, and after each save keeps them again from what was saved. It passes the same `ProfileStoreContract` as the in-memory store. `AppStateDefaultsTests.onlyTheFlagsNameAndSettingsAreWritten` checks nothing else reaches the file.

Reading is careful: a value of the wrong type reads as "not done" or "not seen" (so onboarding or a tour shows again rather than never), an unknown starting closet reads as the sample, and unknown tours or odd versions are ignored. A kept name that breaks the sign's rules, or a setting the app doesn't know, is left out and the default stays. The suite is a plist in the app's container, included in her device backup like any app setting. Simulators have no Data Protection, so the file's protection class on a device hasn't been checked; it doesn't hold anything that needs `complete`. `PrivacyInfo.xcprivacy` now declares the `UserDefaults` API with reason `CA92.1` (data only this app reads). Phase 21a moves all of this into the real stores.

Delete my data erases them with the profile (`LocalDataDeletion`: the profile with its kept name and settings, the tours, then the onboarding state, last), so the app opens on the welcome again with Hello on the sign.

## After a relaunch

Home opens straight away, on the closet she chose, with her name on the sign and her Style Me settings as she left them, and the tours she saw don't come back.

- **Sample closet:** it comes back as it ships, with her name on the sign. The sample's own profile is named Lily, but onboarding asks for her name, so the sample is loaded without it (`FixtureServices`, `unnamed`) and the kept name goes in; a name she skipped stays empty rather than turning into "Lily".
- **Empty closet:** empty again, with her name.
- **What she added or changed apart from those** (pieces, looks, her fit and measurements, the try-on photo) is gone, in either case.

Onboarding (the privacy step's note), Help ("Your data") and Privacy and terms say what's kept and what isn't. Until the Stage A audit the name wasn't kept either, and the sign said Hello after every relaunch.

`-onboarding skip` (every UI test but `OnboardingTests`) keeps nothing: it opens the sample data as it is, so each test starts from the same profile. `-onboarding reset` forgets the kept name and settings with the onboarding state.

## Delete my data

Delete my data now goes back to the welcome, with "Your data is deleted. The app is starting fresh." as a toast, instead of to an empty Home. Finishing onboarding again builds a new closet: she can choose the sample or the empty one. The "Afterwards" words on Delete my data and the Your profile row say so.

## Release builds

Since Phase 20a, Release builds ship no sample data. `AppLaunch.offersSampleCloset` is false there, so onboarding has three steps (name, privacy, fit), the fit step finishes with Go to my room, and she starts on an empty closet, also from "I already use Nifty Outfit Nook", whose VoiceOver hint drops "with the sample closet". Debug builds, and so every test, keep all four steps. `OnboardingModelTests.withoutTheSampleClosetThereAreThreeStepsAndAnEmptyCloset` covers the Release path.

## The debug flag

Debug builds take `-onboarding`:

- `-onboarding reset`: forget that onboarding was finished, and the kept name and settings, so the app opens on the welcome. With `-tour reset` it's a fresh install for the tours too: `-onboarding reset -tour reset -fixtures demo`.
- `-onboarding skip`: open Home straight away for this launch, on the `-fixtures` set as it is (the demo with "Lily" on the sign), reading and writing nothing that's kept. Every UI test passes it except `OnboardingTests` (`UITestLaunch.standard`).

`scripts/check-release.sh` checks the flag isn't in a Release build. `-fixtures` still picks the sample data: the sample closet is the set it names (the demo if it names `empty`), and the empty closet keeps its other options (`slow`, `weather=` and so on).

Since the onboarding state and the tours seen now outlive a launch, also between UI tests on one simulator, each UI test sets what it relies on with these flags instead of counting on a fresh start.

## The welcome on screen

From the mockup, in its 390-point stage: the sky with the words and two clouds, the roof's edge (tiled across the window), the siding and skirt board, the front door with its lantern, mat and pots, a plant, the peg rail with a coat and a tote, the bench with sneakers, and the porch. The sky, siding, roof and porch run the full width; the door and its props stay in the stage in the middle, as the mockup's note asks, so an iPad window doesn't stretch them. The words and buttons keep to a 520-point column, centred on an iPad.

The stage scales between 0.6 and 1.6 times to fit the height between the words and the buttons, sitting right under the words; a taller screen gets more porch, as in the mockup.

New art (`art/room/README.md`): the mockup's `welcome-*` drawings, the porch bench and the sneakers, copied as they are, and `welcome-siding.svg`, drawn from the mockup's CSS bands. The coat is the app's own garment drawing (a tan layer), since the mockup's camel trench comes from `garments.js`. The sky is two new colour tokens, `skyTop` and `skyBottom`: the mockup's blue sky given the windows' treatment in light, and a warm evening sky in dark, so the light words on it stay readable (a dimmed day sky gave them 2.6:1). Both pairs are in `ContrastRequirement`.

## Accessibility

- **VoiceOver order.** Welcome: the title (a heading), the line, Get started, I already use (with the hint "Skips the setup and opens your room with the sample closet."). The drawing is hidden. Each step: its title (a heading), "Step 1 of 4", the line, the content, Continue, Skip for now. The bar's title names the step for Back.
- **Large text.** At the accessibility sizes the welcome puts the buttons straight after the words, so Get started is on the first screen, with the porch after them; the page scrolls. Each step drops its drawing and steps the title down one style, and its buttons follow the content instead of staying at the bottom, where they'd take half the screen.
- **Reduce Motion.** Nothing on the welcome moves. Onboarding hands over to the tabs with a 0.3-second cross-fade, or none with Reduce Motion. The steps use the system's push.
- **Dark.** The evening sky, the art in lamplight, and the tokens everywhere else.
- **iPad.** The welcome's column is centred and the scene fills the window (portrait and landscape); each step is a readable pane. Checked on the 11-inch iPad in both orientations.

## States

Nothing loads but the onboarding state, which is local and quick, so the root shows the wall colour for that moment. A store that can't be read opens onboarding. A failed save on finishing stays on the step with its note. There's nothing to be offline for.

## Tests

- `OnboardingTests` (Models): answers into the profile, a skipped fit, I already use.
- `TourTests` (Models): versions seen before this session count, and records add to them.
- `StoreContractTests` (Fixtures) and `AppStateContractTests` (Services): the profile contract on `KeptSettingsProfileStore`, with the in-memory keeper and with the `UserDefaults` one.
- `OnboardingFixtureTests` (Fixtures): the store, failing with the other stores, each starting closet (the sample without a name, the empty one, the launch options kept), and the stores kept across launches passed through and erased by Delete my data. `DataDeletionFixtureTests` checks onboarding is erased too.
- `AppStateDefaultsTests` (Services): each test on a suite of its own, removed afterwards. Onboarding and tours kept across a "relaunch" (a second store on the same suite), the switch, Reset all tips, erasing, damaged values, a lower version never replacing a higher one; the name and settings kept across a relaunch while fit and measurements aren't, a cleared name, a refused save, changes made at once keeping the latest, erasing and damaged values; and only those keys written.
- `OnboardingModelTests`, `AppRootModelTests` (Features): the steps, the name rules, skipping, the fit toggle, finishing and a failed finish, I already use, the flag; a fresh install, finishing, the empty closet, a relaunch on each closet keeping the name and settings but not the fit, `skip` keeping nothing, `reset` forgetting them, a failed save, Delete my data and an unreadable store.
- `OnboardingSnapshotTests` (16 images): the welcome on the iPhone 17 in light, dark and AX5, on the iPhone SE, and on the 11-inch iPad both ways; each step, a name that's too long, the empty closet in dark, the privacy step in dark, AX5 and on the iPad.
- UI, `OnboardingTests`: from `-onboarding reset -tour reset` through every step to Home's tour, the laptop, Style Me's tour, Style me and the first look; then a relaunch with no flags opens Home with her name on the sign, with no welcome, no Home tour and no Style Me tour. And I already use. `SettingsTests` goes from Delete my data to the welcome, through onboarding with the empty closet, to Home's tour.

## Decisions for Jose

1. **The name is kept across launches** since the Stage A audit, with the Style Me settings (see After a relaunch). Phase 17 kept only the onboarding flags and tours seen.
2. **The tour records are split.** The seen versions and the switch are kept; how each tour ended and when stay in memory. The data map's tour row is split the same way.
3. **The sample closet loads without the name "Lily"** after onboarding, so the sign shows what she typed this session and Hello after a relaunch.
4. **Four steps after the welcome.** The mockup's note says the welcome is the only step; the PRD asks for a name, the privacy explanation and optional fit, and Jose's brief for the starting closet. Every step but the privacy one can be skipped, and I already use skips them all.
5. **No measurements in onboarding**, only usual fit.
6. **I already use Nifty Outfit Nook is kept** from the mockup. In Stage A there's nothing to bring back, so it opens the sample closet without asking anything. From Phase 21b it offers **Get my closet from iCloud** and **Restore from a backup file** (`docs/decisions/0004-backup-and-recovery.md`, New phone and lost phone).
7. **No Welcome tour.** The mockup has one; it would point at the only two buttons on a screen that already explains them, and its first card says "Hello, Lily" before she has typed a name.
8. **Delete my data goes to the welcome**, not to an empty Home, so she can choose a starting closet again.
9. **The welcome's sky is a warm evening in dark**, two new tokens.

## Needs a device

- The Data Protection class of the `UserDefaults` file under the app's `NSFileProtectionComplete` default, and reading it after a reboot before the first unlock (the app never runs in the background, so it shouldn't come up).
- Relaunching after iOS ends the app in the background, as opposed to a test's `terminate()`.
- VoiceOver through the steps and the hand-over to Home's tour.
