# Lily's TestFlight build

> **Since Phase 20a (20 October 2026), a Release archive has no sample data.** It starts on an empty closet and, until real storage arrives in Phase 21a, keeps nothing Lily adds. Some wording below and in the app (the Help version line, What to Test) still describes the sample closet. Jose decides whether to upload before 21a; see `docs/decisions/0003-persistence-spike.md`.

Phase 18, 16 October 2026. How to get the Stage A app onto Lily's iPhone through TestFlight, as an internal build with sample data only, and how her notes come back. Spec: `closet/SWIFT_BUILD_PLAN.md` (Phase 18), `closet/SECURITY_STANDARD.md` §9 and §11, and `closet/DATA_MAP.md` (TestFlight feedback and crash reports).

Nothing here was uploaded, created or sent by an agent. Every step in App Store Connect and every signed build is Jose's.

## What's where

| File | Holds |
|---|---|
| `NiftyOutfitNook/AppIcon.icon` | The placeholder app icon (Icon Composer), described in `art/app-icon/README.md` |
| `Configs/Version.xcconfig` | `MARKETING_VERSION` (0.1.0) and the default build number |
| `scripts/bump-build.sh` | Sets the build number for the next archive, in the ignored `Configs/Build.local.xcconfig` |
| `Configs/AppInfo.plist` | The one Info.plist key the build settings can't set: the launch screen's colour |
| `Configs/ExportOptions-TestFlight.plist` | Upload options for the command-line path: App Store Connect, TestFlight Internal Only |
| `scripts/check-archive.sh` | Makes an unsigned Release archive and checks what would be uploaded |

## What this build is

- Version **0.1.0**. The build number is the UTC date and time it was archived, such as `20261016.1420` (see "Versioning" below).
- **Her data is kept (since Phase 21a).** A Release build has no sample data (Phase 20a) and keeps everything Lily adds or changes in the real store on the iPhone, so it's there after the app closes, until she uses Delete my data. The first launch of a 21a build moves what earlier builds kept (her name on the sign, her Style Me settings, onboarding done, the tips seen) into it. Onboarding (step 2), Privacy and terms and Help say so. The Help version line still reads "Nifty Outfit Nook · 0.1.0 (20261016.1420) · test build with sample data", which 20a listed for Jose.
- No network, no account, no permissions, no analytics. The one web address in the app is the website, for Privacy and terms, and it opens only when she taps it. Those pages are still the "Coming soon" page (Phase 19b writes them).
- **Internal only.** The upload is marked TestFlight Internal Only, so this build can never go to external testers or the App Store, even by mistake.

## Versioning

- `MARKETING_VERSION` stays `0.1.0` for every Stage A build. It goes up when a release branch is cut for the App Store (Git Flow, `closet/SWIFT_BUILD_PLAN.md`).
- `CURRENT_PROJECT_VERSION`, the build number, must be higher for every upload of the same version. Run `scripts/bump-build.sh` before each archive. It writes the current UTC date and time to `Configs/Build.local.xcconfig`, which git ignores, so a new build never needs a commit and a later build always has a higher number on any Mac. Without it the build number is `1`, and App Store Connect refuses a second upload of `1`.
- `scripts/bump-build.sh 20261016.1500` sets a number of your own. A build number is one to three whole numbers joined by dots.

## One-time setup (about 20 minutes)

### 1. Your team in the project

```sh
cp Configs/Signing.local.xcconfig.example Configs/Signing.local.xcconfig
```

Open `Configs/Signing.local.xcconfig` and replace `YOUR_TEAM_ID` with your team ID (developer.apple.com > Account > Membership details). The file is ignored by git. Set the team only there, not in Xcode's Signing & Capabilities tab: that writes `DEVELOPMENT_TEAM` into `project.pbxproj`, which is committed, and this repo is public.

### 2. The App ID

In Certificates, Identifiers & Profiles (developer.apple.com > Account), Identifiers > **+** > App IDs > App:

- Description: `Nifty Outfit Nook`
- Bundle ID: Explicit, `com.jsayram.niftyoutfitnook`
- Capabilities: **Data Protection**, set to **Complete Protection**. The app asks for it (`NiftyOutfitNook.entitlements`). Nothing else.

Xcode's automatic signing would register it on the first archive too, with the same capability, but doing it here means the bundle ID is ready for the next step.

### 3. The app record in App Store Connect

App Store Connect > Apps > **+** > New App:

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | `Nifty Outfit Nook` (the store name; the home screen shows "Outfit Nook") |
| Primary Language | English (U.S.) |
| Bundle ID | `com.jsayram.niftyoutfitnook` |
| SKU | `niftyoutfitnook-ios` (only you see it; it can't be changed later) |
| User Access | Limited Access, with no one added, unless you want someone else in it |

If the name is taken, App Store Connect says so here. The name can change before release; the bundle ID and SKU can't.

Then, under App Information, set the **Primary Category** to **Lifestyle** (it matches `LSApplicationCategoryType` in the app). Leave the secondary category empty. Nothing else on the store page is needed for TestFlight.

### 4. Lily as an internal tester

Apple's current rules (App Store Connect Help, "Add internal testers", checked 16 October 2026):

- Internal testers must be **App Store Connect users on your team**, with the Account Holder, Admin, App Manager, Developer or Marketing role. There's no tester-only role.
- Up to 100 internal testers. Internal builds need **no App Review** and are ready as soon as App Store Connect has processed them. Each build can be tested for 90 days.
- External testing would avoid making her a team user, but the first build of each version then waits for Beta App Review, and this build is marked internal only anyway.

So, the smallest access that works:

1. Users and Access > **+**. Her name and the email address of her Apple Account (the one on her iPhone is simplest).
2. Role: **Marketing**, the narrowest of the five. Under Apps, choose **Nifty Outfit Nook** only, not all apps. Leave every other option off.
3. She gets an email from App Store Connect and accepts it, signing in with that Apple Account. She doesn't need to use App Store Connect after that.
4. TestFlight > Internal Testing > **+** to make a group, for example `Lily`. Turn on automatic distribution if you want each new build to reach her without adding it by hand. Add Lily to the group (only accepted team users can be added).

When the work no longer needs her as a tester, remove her from Users and Access.

## Each build (about 15 minutes, plus processing)

1. Be on an up-to-date `develop`, with a clean tree: `git checkout develop && git pull`. TestFlight builds come from `develop`.
2. `scripts/bump-build.sh`
3. Optional, two minutes: `scripts/check-archive.sh` makes an unsigned archive and checks it (see "Release checks").
4. Open `NiftyOutfitNook.xcodeproj` in Xcode. Choose the `NiftyOutfitNook` scheme and **Any iOS Device (arm64)** as the destination.
5. Product > **Archive**. When it's done, the Organizer opens with the new archive (version 0.1.0 and the build number from step 2).
6. **Distribute App** > **TestFlight Internal Only** > Distribute. Xcode signs it with your distribution certificate (it makes one if you don't have it yet) and uploads it.
   - If Xcode asks about **export compliance**, the answer is that the app uses no encryption beyond what's in iOS. It shouldn't ask: the app's Info.plist already says `ITSAppUsesNonExemptEncryption` = NO, and App Store Connect reads that. Phase 21b rechecks this answer when encrypted export arrives (AppleArchive's encryption, which is Apple's own; `docs/decisions/0004-backup-and-recovery.md`).
   - If it offers to manage the version and build number, leave that off, so the build number in Help matches App Store Connect.
7. In App Store Connect > TestFlight, the build shows "Processing" for a few minutes, then "Ready to Test". Open it, paste the **What to Test** text below, and save. Add it to the `Lily` group unless automatic distribution did.
8. Lily gets an email (and a TestFlight notification after the first time).

The command-line version of steps 4 to 6, with the same settings:

```sh
xcodebuild archive -project NiftyOutfitNook.xcodeproj -scheme NiftyOutfitNook -configuration Release \
    -destination "generic/platform=iOS" -archivePath build/Archives/NiftyOutfitNook.xcarchive \
    -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/Archives/NiftyOutfitNook.xcarchive \
    -exportOptionsPlist Configs/ExportOptions-TestFlight.plist -exportPath build/Export \
    -allowProvisioningUpdates
```

`Configs/ExportOptions-TestFlight.plist` uploads (`destination` upload) as TestFlight Internal Only, keeps the build number, and uploads symbols. It holds no team ID; the team comes from the archive. Either path needs Xcode signed in to your developer Apple Account (in Xcode's Settings).

### Lily's side

1. Install **TestFlight** from the App Store.
2. Open the invitation email on her iPhone and tap **View in TestFlight**, then **Accept** and **Install**.
3. "Outfit Nook" appears on her home screen with an orange dot while it's a beta.

## What to Test (paste into App Store Connect)

Under 4,000 characters, as App Store Connect requires.

```text
Hi Lily! This is the first test of Nifty Outfit Nook on your phone.

It runs on sample data. Your name and your Style Me settings in Profile stay when the app closes. Everything else you add or change goes away, and the sample closet comes back. Nothing is sent anywhere, and it doesn't ask for your camera, photos or location yet. Style Me uses a stand-in stylist for now, so the looks are only examples.

Things to try, in any order:
- Set it up: your name for the sign, then the sample closet (or an empty one).
- Home: tap things in your room. The quick tips show the first time.
- Closet: look through the pieces, search, use the filters, open a piece.
- Add a piece with a sample picture, then edit it.
- Style Me: pick an occasion and get a look. Switch between Simple, Dressed up and Something new, try a different outfit, swap a piece, and save a look you like.
- Saved Looks, Suitcases and Laundry.
- Profile: your fit, the app tips, and Help.
- Turn your phone sideways, try the dark appearance, and bigger text in Settings.

Please tell me about anything that's confusing, hard to read or tap, slow, ugly, or broken, and anything you love. The easiest way: take a screenshot in the app, tap the little picture in the corner, tap Done, then Share Beta Feedback and write what you noticed. You can also open TestFlight, tap Outfit Nook and Send Beta Feedback. If it crashes, you'll get an alert where you can tap Share and add a note.

Thank you!
```

## How her notes come back

The usual sign-off process (`closet/prototypes/RoomDirectionMockups/README.md`, "Lily's notes: pull, sign off, run"). Nothing she reports changes the app until you approve it.

1. Her screenshots, notes and crash reports arrive in App Store Connect > TestFlight > Feedback, and in the Organizer's Feedback and Crashes tabs in Xcode. Only you can see them. `closet/DATA_MAP.md` lists them as Personal (a screenshot can show what she typed), kept until you delete them.
2. Copy what's useful into the closet repo as text, plus any screenshot she's happy to have there (the repo is public, so leave out anything personal). Say **"Pull Lily notes"**: the agent writes the numbered sign-off sheet from them (L1, L2…, her words, a proposed fix, UI or Needs a talk) and changes nothing.
3. You approve or decline each item. **"Run Lily notes"** builds only the approved ones, as a phase branch through the usual PR, and the next TestFlight build carries them.

No agent can read TestFlight feedback: that would need an App Store Connect API key, and none exists (`closet/ACCOUNT_INVENTORY.md`).

## Release checks

Run on 16 October 2026 against an unsigned Release archive (`scripts/check-archive.sh`, Xcode 26.6, iOS 26.5 SDK).

| Check | Result |
|---|---|
| Archive builds without signing (`CODE_SIGNING_ALLOWED=NO`) | Yes, in about a minute |
| Bundle ID, display name, version | `com.jsayram.niftyoutfitnook`, "Outfit Nook", 0.1.0 |
| Build number | `1` by default, the bump-build value when set (checked with `2`) |
| `ITSAppUsesNonExemptEncryption` | NO |
| Usage-description (permission) keys | None |
| App Transport Security keys | None |
| Background modes | None |
| Devices and minimum iOS | iPhone and iPad, iOS 26.0, arm64 |
| Orientations | iPhone: portrait and both landscapes. iPad: all four. Home and Closet have sideways layouts (Phases 5b, 15a) |
| Launch screen | The wall colour (`LaunchBackground`, light `#F4EEE6`, dark `#211B16`) instead of white or black |
| App icon | `AppIcon` from `AppIcon.icon`, with the 60 and 76 pt fallback PNGs the build makes |
| Privacy manifest | In the app. No tracking, no tracking domains, no collected data. Two required-reason APIs: `UserDefaults`, reason `CA92.1` (since 21a only read once, to move Stage A's suite into the store), and disk space, reason `E174.1` (since 21a: the migration checks there's room for its safety copy before it starts). No file timestamps, boot time or keyboards (the store's sizes are read with `fileSizeKey`) |
| Entitlements | Only Data Protection, `NSFileProtectionComplete`. Signing adds the usual team, app ID and `beta-reports-active` |
| Test code | No `.xctest`, no `Frameworks` or `PlugIns` folder. The binary doesn't link XCTest, Swift Testing or swift-snapshot-testing. `scripts/check-release.sh` on the device binary: no catalog, cutout benchmark or debug launch flags |
| Debug symbols | The binary is stripped (only imported symbols left). The dSYM is separate, with the same UUID, for crash reports. No path from the build Mac in the binary |
| Secrets | None. No keys, tokens or passwords in the binary's strings or the repo (gitleaks) |
| Size | App 15 MB (binary 7.1 MB, art 7.6 MB), about 10 MB zipped. dSYM 36 MB |

## Decisions for Jose

1. **The icon is a placeholder**: a dress on a hanger in an arched nook. Replace it whenever you like (`art/app-icon/README.md`).
2. **Build numbers are timestamps** (`20261016.1420`) in an ignored file rather than a committed counter, so a build never needs a PR. The cost: the build number isn't in git. The archive and App Store Connect both keep it.
3. **Lily's role is Marketing**, limited to this app. It's the narrowest role Apple allows for an internal tester; it can still see the app's store page and marketing settings.
4. **Internal only.** Every upload is TestFlight Internal Only while the app carries sample data.
5. **The launch screen is the wall colour.** Onboarding's first screen is the sky, so a first launch goes from the wall colour to the sky. Later launches open on the room.

## Needs Jose

Everything in "One-time setup" and "Each build". The agent did not create the App ID or the app record, sign, upload, or invite anyone.
