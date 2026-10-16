# Quick tours

Phase 16a, 15 October 2026. One tour system for every screen, and Home's tour. Spec: PRD §7.8, FR-73, TourProgress / TourPreferences in §12 and AC-103; amendment LR-02 (the tour in the warm palette instead of plum). Visual references: `home-tour.html`, `home-ax-tour.html`, `home-landscape-tour.html`, `ipad-home-tour.html` and `ipad-home-portrait-tour.html` in `closet/prototypes/RoomDirectionMockups/screens`, with `css/home-tour.css` and the copy in `js/screen-tours.js`.

Phase 16b adds the other screens' tours, App tours in Profile (replay, and the "Show tips on new screens" switch), and keeping progress across launches.

## What's where

| File | Holds |
|---|---|
| `Models/Tours/TourProgress.swift` | `TourID`, `TourOutcome`, `TourRecord`, `TourProgress`, `TourRules` and the `TourProgressStore` protocol |
| `Models/Tours/TourRun.swift` | One tour while it shows: the step, Next, Back, and the record when it ends |
| `Fixtures/Stores/InMemoryTourProgressStore.swift` | Stage A's store, in memory |
| `DesignSystem/Components/Tour/` | `NookTourOverlay` (the dim, the spotlight, the tail and the card), `NookTourCard`, and `NookTourPlacement`, which decides where the card goes |
| `Features/Tours/TourCenter.swift` | Runs the tours: starting, the buttons, anchors, recording |
| `Features/Tours/TourAnchor.swift` | `.tourAnchor(_:label:hint:action:)`, `.tourFocusTarget(_:)` and `TourScrollReader` |
| `Features/Tours/TourOverlay.swift` | Draws the tour that's showing over the whole window |
| `Features/Tours/TourDefinition.swift`, `TourLaunchOptions.swift` | A tour's steps and words, and the `-tour` debug flag |
| `Features/Home/HomeTour.swift` | Home's four steps, in the words for each layout |

## How a screen gets a tour

1. Write its `TourDefinition`: a stable `TourID`, a content version, the steps (an anchor, a title and a sentence or two each) and the last button's words. Every layout of the screen shares the ID and the steps; only the words may differ.
2. Mark each control a step points at with `.tourAnchor(id, label:, hint:, action:)`. The label is what VoiceOver calls the control, the action is what a tap in the spotlight does (the control's own action). Each layout marks its own view with the same anchor. Mark the control VoiceOver should land on afterwards with `.tourFocusTarget(id)`. When the drawing to light up is bigger than the button (Home's furniture), anchor an invisible view the drawing's size and put the focus target on the button.
3. Wrap any scroll view the controls live in with `TourScrollReader`, so each one is scrolled into view as the tour reaches it.
4. Once the screen's controls are ready, call `tours.startIfNeeded(definition) { isReady }` from the screen's `.task`, where `isReady` says nothing else is on top (a pushed screen, a sheet, a toast). When the layout changes, call `tours.update(definition)` so the words follow and the step stays.

The root view keeps one `TourCenter` for the app and draws the tour over the tab view, so the dim covers the bars and the tab bar can't be tapped through it. `TourCenter` lives above the part of the root that Delete my data rebuilds.

## When a tour starts

By itself, once a session, when tips are on and she hasn't seen this version (`TourRules.startsAutomatically`). Finished, skipped and "tapped the highlighted control" all count as seen. A version goes up only when the controls or the steps really change, never for copy fixes. A store that can't be read means no tour (tours are optional), and a write that fails only means the tour may show again next launch.

Home's starts the first time Home shows, after its model has loaded, and never over a pushed screen, a sheet or a toast. After Delete my data the toast is said first, then the tour starts, as on a fresh install: Delete my data erases the tour progress with the profile and turns tips back on.

In Stage A progress is in memory, so every launch is a first visit, like a fresh install. Phase 21a puts it on disk with the other preferences.

## The tour on screen

- **The dim** is the warm ink at 58% (`tourScrim`), not the mockup's plum (LR-02). It takes every tap, so nothing under it opens by accident.
- **The spotlight** is a cut-out with 22-point corners around the control, 8 points bigger on every side, with a soft edge, a warm glow and a blurred light rim. No hard outline (RD-05).
- **The card** is the plate colour, opaque, with 26-point corners, a soft shadow below and a tail aimed at the control. It goes below or above the control, on the side with more room; beside it when neither fits (a tall wardrobe on a wide iPad, or the sideways phone); on its own, with no spotlight, when it can't sit clear of the control (the largest text sizes); and in the middle, with no spotlight, when the control isn't on screen. It's 300 points wide, 340 at the larger standard sizes and up to 480 at the accessibility sizes, inside the safe area.
- **Buttons**: Back (from step 2), Skip and Next, which says what to do next on the last step ("Start styling" on Home). Next is the default action and Skip the cancel action, for Return and Escape on a hardware keyboard (not yet checked on a device; see below). When the buttons don't fit beside the dots they move under them, and at the largest sizes they stack at full width. When the words are taller than the screen they scroll inside the card and the buttons stay put.
- **Tapping the spotlight** ends the tour, recorded as `controlActivated`, then does what the control does, once.
- **Motion**: the spotlight and card glide to each step in 0.3 seconds. With Reduce Motion each step cross-fades instead, and scrolling a control into view jumps rather than scrolls.
- **Rotation, window resizes, text size, scrolling**: anchors report their frame in the window whenever it changes (`onGeometryChange`), so the spotlight follows. A new layout of the screen (sideways, large text, an iPad window) keeps the step and swaps in its own words.

## VoiceOver and the keyboard

- While a tour shows, the overlay is modal (XCUITest sees it as an alert), so VoiceOver stays in it. The screen under it is also marked hidden from VoiceOver.
- The card comes first. VoiceOver follows the order things are drawn in, so the highlighted control's own button is drawn after the card (they never overlap). The card's words are one element, read as "Quick tour, step 1 of 4. Style Me. Tap the laptop and I'll pull together a look... Highlighted: Laptop: Style Me." VoiceOver moves to it on every step.
- Then Back, Skip and Next, and the highlighted control itself, as a button with its usual label and the hint "Ends the tour." plus its own hint.
- The VoiceOver escape gesture (two-finger scrub) and Escape on a keyboard call Skip. Neither can be sent from a UI test, so both are on the list below.
- When the tour closes, VoiceOver goes to the control of the step that was showing, or to Style Me after Start styling.

PRD §7.8 says Next is focused first. On iOS that would read only "Next, button", so VoiceOver starts on the card's words instead, which say the step and what it's about; Next is two swipes on. Return still means Next on a keyboard.

## Home's tour

Laptop (Style Me), wardrobe (Closet), suitcase (what Style Me picks from), name sign (Profile), then Start styling, as approved. The words come from the mockups for each layout:

| Layout | Words from | Points at |
|---|---|---|
| The phone's room | `home-tour.html` ("Packing from", "That's you") | The drawn laptop, wardrobe, suitcase and sign |
| The iPad's tall and wide rooms | `ipad-home` in `screen-tours.js` | The same, where the iPad room puts them |
| Large text | `home-ax` ("Tap here...", "Your suitcase", "That is you") | The Style Me button, the banner's wardrobe, the Source row, the banner's sign |
| A phone held sideways | `home-landscape`, the same words as large text | The Style Me button, the scene's wardrobe, the Source tile, the scene's sign |

## Debug flag

Debug builds take `-tour` with one or more values, separated by commas:

- `-tour home`: start Home's tour when Home first shows, whatever is recorded.
- `-tour reset`: forget the tours seen and turn tips back on, before anything starts.
- `-tour off`: turn tips off, so no tour starts by itself. Every UI test passes this except the tour's own.

For example `-fixtures demo -tour reset,home`. `scripts/check-release.sh` checks the flag isn't in a Release build.

## Tests

- `TourTests` (Models): stepping through a run, Back, the record, and when a tour may start.
- `TourStoreTests` (Fixtures): the store, every set starting fresh, and failing with the other stores. `DataDeletionFixtureTests` checks Delete my data resets it.
- `TourPlacementTests` (DesignSystem): below, above, beside, alone, and in the middle with no control; the card's width; what VoiceOver reads.
- `TourCenterTests` (Features): starting once, the buttons, what each way out records, tips off, a store that fails, the screen not ready, the debug flag, a new layout keeping the step, anchors and their owners, and a control out of sight getting no spotlight.
- `HomeTourSnapshotTests`: each of the four steps on iPhone 17, a step in dark, AX5, and the wide room on the 11-inch iPad sideways. `ComponentSnapshotTests` adds the catalog's "Quick tour card" page (`-catalog-page tour`).
- `HomeTourTests` (UI): completing the tour with Back on the way, skipping it, tapping the highlighted control, the tour being modal (the card's words first, nothing under the dim can be tapped), the tour at AX5, and the debug flag. `SettingsTests` checks the tour starts again after Delete my data, once the toast has gone.
- `IPadTests` (UI): the spotlight follows the wardrobe through rotation and a narrow window, keeping the step.

### Needs a check with VoiceOver on

UI tests can't run VoiceOver, and on the iOS 26.5 simulator `typeKey(.escape)` reached neither Skip's `.keyboardShortcut(.cancelAction)` nor a focused `.onKeyPress(.escape)`, as 15b found for its shortcuts. On a device (an iPad with a keyboard for Escape) with VoiceOver on: focus lands on the card's words on each step; Escape and the two-finger scrub skip; activating the highlighted control opens it; nothing under the dim can be reached; and focus lands on that step's control when the tour closes.

## Decisions for Jose

1. **The card is opaque.** The mockup's card is 94% white over a 14-point blur. Without the blur the room's words showed through the card, so it's the plate colour, solid. The dim, glow and corners follow the mockup in warm tones.
2. **VoiceOver starts on the card's words, not on Next** (see above).
3. **Back was added**, from step 2, as a small chevron. The mockup has only Skip and Next.
4. **The tab bar is dimmed and covered too**, so nothing can be tapped through the tour. The card can sit over the tab bar when that's the only room left (the wardrobe step on iPhone).
5. **The last Home step says "You can replay this tour from it any time."** Replay arrives with 16b's App tours row; until then the line is ahead of the app.
6. **Delete my data's list doesn't name tour progress yet.** It's erased with "Your profile"; the words under that row change in 16b, when the tips switch appears in Profile.
7. **At the largest text sizes the card usually shows without a spotlight**, because a card that tall can't sit clear of a row. The words still say what the step is about, and the page behind has scrolled to the row.
