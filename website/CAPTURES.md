# Website capture provenance

Updated 21 October 2026. These are actual SwiftUI test snapshots from merged app commit `fccb620369c7ca94ff36db37f2a70d20189fac97`, converted to WebP with `cwebp -q 86 -metadata none`. The working checkout was not built or modified. Snapshot fixtures use fictional/sample data; service, account and try-on simulations remain labelled. Timeline dates refer to verified milestones, not screenshot creation dates; current previews are not represented as historical captures.

The early room mockup is the planning repo's `prototypes/RoomDirectionMockups/snapshots/home--default.png`, explicitly labelled with the previous working title and palette. `app-weather-controls.webp` is a crop (x 0, y 780, width 402, height 330) of the full `app-weather.webp`; enlargement opens the original full screen.

| Asset | Snapshot source | Last source change |
| --- | --- | --- |
| `home-preview-light.webp` | `Packages/NookKit/Tests/FeaturesTests/Home/__Snapshots__/HomeSnapshotTests/room-phone.iPhone17.png` | 2026-10-16 |
| `home-preview-dark.webp` | `Packages/NookKit/Tests/FeaturesTests/Home/__Snapshots__/HomeSnapshotTests/darkRoom.dark.png` | 2026-10-16 |
| `app-closet.webp` | `Packages/NookKit/Tests/FeaturesTests/Closet/__Snapshots__/ClosetSnapshotTests/demoCloset.demo.png` | 2026-10-17 |
| `app-style-request.webp` | `Packages/NookKit/Tests/FeaturesTests/StyleMe/__Snapshots__/StyleMeSnapshotTests/defaultRequest.default.png` | 2026-10-16 |
| `app-ai-looks.webp` | `Packages/NookKit/Tests/FeaturesTests/StyleMe/__Snapshots__/YourLooksSnapshotTests/simple.simple.png` | 2026-10-17 |
| `app-try-on.webp` | `Packages/NookKit/Tests/FeaturesTests/SavedLooks/__Snapshots__/SavedLooksSnapshotTests/pictureDetail.picture.png` | 2026-10-17 |
| `app-suitcases.webp` | `Packages/NookKit/Tests/FeaturesTests/Suitcases/__Snapshots__/SuitcasesSnapshotTests/suitcases.suitcases.png` | 2026-10-17 |
| `app-laundry.webp` | `Packages/NookKit/Tests/FeaturesTests/Suitcases/__Snapshots__/SuitcasesSnapshotTests/laundryWithASuitcaseSource.laundry.png` | 2026-10-17 |
| `app-add-photo.webp` | `Packages/NookKit/Tests/FeaturesTests/AddPiece/__Snapshots__/GarmentEditorSnapshotTests/choicesWithPaste.choose-paste.png` | 2026-10-21 |
| `app-piece-details.webp` | `Packages/NookKit/Tests/FeaturesTests/AddPiece/__Snapshots__/GarmentEditorSnapshotTests/filledForm.filled.png` | 2026-10-20 |
| `app-search-matches.webp` | `Packages/NookKit/Tests/FeaturesTests/Closet/__Snapshots__/ClosetSnapshotTests/possibleMatches.possible-matches.png` | 2026-10-21 |
| `app-remember-name.webp` | `Packages/NookKit/Tests/FeaturesTests/Garment/__Snapshots__/GarmentDetailSnapshotTests/rememberThisName.remember.png` | 2026-10-21 |
| `app-saved-all.webp` | `Packages/NookKit/Tests/FeaturesTests/SavedLooks/__Snapshots__/SavedLooksSnapshotTests/allScopeDark.all-dark.png` | 2026-10-21 |
| `app-saved-looks.webp` | `Packages/NookKit/Tests/FeaturesTests/SavedLooks/__Snapshots__/SavedLooksSnapshotTests/savedWithMoreInAllAboveTheTabBar.saved-more-in-all-on-screen.png` | 2026-10-21 |
| `app-backups.webp` | `Packages/NookKit/Tests/FeaturesTests/Settings/__Snapshots__/BackupsSnapshotTests/backupsScreen.backups.png` | 2026-10-20 |
| `app-restore.webp` | `Packages/NookKit/Tests/FeaturesTests/Settings/__Snapshots__/BackupsSnapshotTests/restoreSheet.restore-preview.png` | 2026-10-20 |
| `app-weather.webp` | `Packages/NookKit/Tests/FeaturesTests/Settings/__Snapshots__/SettingsSnapshotTests/privacyWeather.privacy-weather-city.png` | 2026-10-21 |
| `app-weather-home.webp` | `Packages/NookKit/Tests/FeaturesTests/Home/__Snapshots__/HomeSnapshotTests/liveWeather-condition.weather-snow.png` | 2026-10-21 |
| `app-account-control.webp` | `Packages/NookKit/Tests/FeaturesTests/Settings/__Snapshots__/SettingsSnapshotTests/deleteAccountScreen.delete-account.png` | 2026-10-21 |
| `app-onboarding.webp` | `Packages/NookKit/Tests/FeaturesTests/Onboarding/__Snapshots__/OnboardingSnapshotTests/welcomeScreen.welcome.png` | 2026-10-16 |
| `app-tour.webp` | `Packages/NookKit/Tests/FeaturesTests/Tours/__Snapshots__/ScreenTourSnapshotTests/addPiecePhotos.add-piece-1.png` | 2026-10-16 |
| `app-ipad.webp` | `Packages/NookKit/Tests/FeaturesTests/Closet/__Snapshots__/ClosetIPadSnapshotTests/sidebarOn11InchSideways.11-landscape.png` | 2026-10-17 |
| `app-components.webp` | `Packages/NookKit/Tests/DesignSystemTests/__Snapshots__/ComponentSnapshotTests/iPhone-demo.chips-light.png` | 2026-10-14 |
| `app-pack.webp` | `Packages/NookKit/Tests/FeaturesTests/Suitcases/__Snapshots__/SuitcasesSnapshotTests/packingSheet.packing.png` | 2026-10-17 |
| `app-offline.webp` | `Packages/NookKit/Tests/FeaturesTests/StyleMe/__Snapshots__/YourLooksSnapshotTests/offlineWithLooks.offline-with-looks.png` | 2026-10-17 |

## Milestones added 23 October 2026

Actual merged app snapshots from `413cdfd600c687f595a441df55be190241b2f651`, converted with `cwebp -q 86 -metadata none`. These previews use fictional or drawn test data; no personal photos are published. Milestone dates follow America/New_York, so the iCloud merge at 00:30 UTC on 23 October appears as 22 October locally. Cloud styling, live try-on and iCloud remain inactive pending activation and device validation.

- `app-quick-ideas.webp`: `Packages/NookKit/Tests/FeaturesTests/StyleMe/__Snapshots__/QuickIdeasLabelSnapshotTests/yourLooksWithQuickIdeas.your-looks.png`
- `app-photo-coach.webp`: `Packages/NookKit/Tests/FeaturesTests/TryOn/__Snapshots__/TryOnSetupSnapshotTests/readyWithTheTimerRunning.hint-ready-countdown.png`
- `app-photo-check.webp`: `Packages/NookKit/Tests/FeaturesTests/TryOn/__Snapshots__/TryOnSetupSnapshotTests/aPhotoThatWorks.review-fine.png`
- `app-privacy-veil.webp`: `Packages/NookKit/Tests/FeaturesTests/TryOn/__Snapshots__/PrivacyWalkthroughSnapshotTests/theVeilCoversHerHead.beat-veil.png`
- `app-privacy-sent.webp`: `Packages/NookKit/Tests/FeaturesTests/TryOn/__Snapshots__/PrivacyWalkthroughSnapshotTests/thePhotoGoesToTheImageService.beat-sent-dark.png`
- `app-sign-in.webp`: `Packages/NookKit/Tests/FeaturesTests/Shared/__Snapshots__/SignInSnapshotTests/signInSheet.sign-in-sheet.png`
- `app-report-result.webp`: `Packages/NookKit/Tests/FeaturesTests/Shared/__Snapshots__/SignInSnapshotTests/reportSheet.report-sheet.png`
