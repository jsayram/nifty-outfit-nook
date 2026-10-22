# Accessibility audit and device substitutes

Stage A, 17 October 2026. Jose doesn't have Lily's iPhone 12, so the checks that would need it were moved onto simulators where a simulator can stand in, and the rest are listed for a real device. This note covers the accessibility audit tests, the iPhone 12 simulator run, and what still needs a phone or an iPad. The cutout's part is in `docs/cutout-feasibility.md`, the iPad keyboard's in `docs/ipad.md` (Keyboard shortcuts), and the tours' VoiceOver order in `docs/tours.md`.

## The audit tests

`AccessibilityAuditTests` runs Xcode's accessibility audit (`XCUIApplication.performAccessibilityAudit(for: .all)`) on each main screen at the default text size, whenever the UI tests run, and `AccessibilityAuditLargeTextTests` runs the same walk at AX5 in a manual full-suite run only (one audit per screen is enough). They're the closest a UI test gets to a VoiceOver pass: the audit checks contrast, elements VoiceOver can't find, hit regions under 44 points, missing or weak labels, Dynamic Type, clipped text and traits, on what's on screen when it runs.

| Walk | Screens |
|---|---|
| `testOnboarding` | The welcome and the four steps |
| `testHomeAndItsTour` | Home, and Home with its tour on step 1 |
| `testClosetAndItsScreens` | Closet, a piece, Suitcases, a suitcase, Laundry, Add a piece and its form |
| `testStyleMeAndYourLooks` | Style Me, Your looks (Today and Saved), Swap a piece |
| `testSavedLooksAndPictures` | Saved Looks, Saved Looks on All (the Not saved tag and Save look), a saved look, Pictures, a picture |
| `testProfileAndSettings` | Profile, Fit and measurements, Accessibility, Help, Send feedback, Privacy and terms, Delete my data |
| `testTryOnPhotoAndStylingAccess` | Your try-on photo (the sheet from Profile) and Styling access, the paywall (added in Phase 35a) |
| `testBackups` | Backups, reached through onboarding's empty closet because it shows only for her own closet (35a) |
| `testDeleteMyAccount` | Delete my account, signed in with a subscription that still bills (35a) |

Before each audit the test waits until two screenshots in a row are the same, because the room art, the name sign and look bundles are drawn a moment after a screen appears. Without the wait the audit checked "Lily" against an empty sign.

On CI the default walk runs in `ui-home-and-settings` and the AX5 walk in `ui-add-and-tours`. Locally on the iPhone 17 simulator the default walk took about 3.5 minutes and the AX5 walk about 5; see the pull request for CI.

### What the audit found

- **Fixed: the Simulated badge at AX5.** On a try-on picture it grew until "Simulated" broke over two lines as "Simu-lated" and covered the top of the picture (seen on the iPhone 12, but picture detail is 280 points wide on every phone). It's words on art, like the room's plates, so it now stops growing at xxxLarge; the page under the picture says the picture is simulated at full size, and VoiceOver reads "Simulated try-on picture of …". `TryOnPictureBadgeTests` checks it fits on one line at AX5 and still grows up to xxxLarge.
- Nothing else was real: no hit region under 44 points, no missing label, no element VoiceOver can't reach that it should.

### What's excused, and why

Every issue fails the test unless `AuditExclusions` (in `NiftyOutfitNookUITests/AccessibilityAuditExclusions.swift`) gives a reason. The rules are narrow, and where they can, they check the claim:

| Audit | Excused when | Why |
|---|---|---|
| Contrast | The words measure 4.5:1 or more on screen | The audit flags plainly readable espresso-on-cream text, apparently misreading see-through tints and soft shadows (solid dark buttons pass). Each one is measured again from the screenshot's pixels in the element's frame (`PixelContrast`), and only excused if it reaches 4.5:1 |
| Contrast | The element is under the floating tab bar or in the fade above it | iOS 26 fades content scrolling under a floating bar on purpose |
| Contrast | A quick tour is showing and the element is outside its card | The dim is meant to be dim, and the screen under it is hidden from VoiceOver |
| Contrast | The element runs past the window's edge | A chip in a row that scrolls sideways; the same chips measure fine on screen |
| Contrast | The audit names no element, and every word on screen passes these rules | On the iPhone 17 simulator some contrast issues come with no element ("Contrast failed for SwiftUI.AccessibilityNode"). Every static text and button is read from one snapshot of the app's tree and measured; one that fails is named in the failure |
| Contrast | The control is disabled | WCAG 1.4.3 exempts inactive controls (Laundry's Clean selected before she ticks one) |
| Dynamic Type | "Partially unsupported" only | Every font is a Dynamic Type text style (`NookTextStyle`); the audit flags the same chip on one screen and not another, and flags titles the AX5 walk shows at full size. System bar buttons do stop growing, by design, with the Large Content Viewer. A font that doesn't scale at all still fails |
| Clipped text | Named screen and label, looked at in the screenshots | Fit and measurements' title (tight letter spacing, every letter visible), Add or remove on a suitcase, the Layers chip at AX5, and an element-less report on the welcome |
| Clipped text | No element, while a quick tour shows | The screen under the dim is hidden from VoiceOver, so its words have no element; the card's words do, and still fail if clipped |
| Clipped text | No element, at AX5 on Saved Looks, Pictures, Your looks and Your looks: Saved | New with the iOS 27.0 runtime (19 October 2026): the same code passed on iOS 26.5 with Xcode 27.1. Screenshots attached to each excused issue (iPhone 12, AX5) show the words whole; Pictures was checked on the Looks and Pictures switch it shares with Saved Looks |
| Text VoiceOver can't reach | A tour is showing, Suitcases' hall, or words half under the tab bar | The tour is modal by design; the hall's luggage tags repeat the rows under them and are hidden on purpose; the half-covered words are an element, whole once scrolled |

Found on the iOS 26.5 simulators (iPhone 12 and iPhone 17) with Xcode 26.6. Xcode 27.1 on iOS 27.0 reported the four element-less clipped-text issues in the table and nothing else new. A new Xcode can report different issues, so expect to look at this list again then.

## The iPhone 12 simulator

An iPhone 12 simulator (390 x 844 points, iOS 26.5) stood in for Lily's phone:

- The whole UI suite passed on it: 71 tests, 7 skipped (the iPad ones), none failed.
- A screenshot walk of every main screen at the default size, at AX5 and in dark found one layout problem, the Simulated badge above. Nothing else ran off the screen or overlapped at 390 points.
- The cutout can't run on it (`docs/cutout-feasibility.md`).

## Still needs a real device

- **VoiceOver** on Lily's iPhone (or any iPhone): the tours (`docs/tours.md`, Needs a check with VoiceOver on), onboarding's order, and a pass through the main screens.
- **The cutout go/no-go**: Phase 22a on her iPhone 12 with her photos (`docs/cutout-feasibility.md`).
- **iPad with a keyboard**: Escape, the first key press after launch, and whether the keyboard's bar covers the tab bar (`docs/ipad.md`).
- **Speed and memory** on an A14: the large-closet scroll checks run on the Mac's chip here.
- **Data Protection** on the kept settings file, and a relaunch after iOS ends the app (`docs/onboarding.md`, Needs a device).
