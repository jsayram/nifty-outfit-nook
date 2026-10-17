# Quick tours

Phase 16a, 15 October 2026. One tour system for every screen, and Home's tour. Spec: PRD §7.8, FR-73, TourProgress / TourPreferences in §12 and AC-103; amendment LR-02 (the tour in the warm palette instead of plum). Visual references: `home-tour.html`, `home-ax-tour.html`, `home-landscape-tour.html`, `ipad-home-tour.html` and `ipad-home-portrait-tour.html` in `closet/prototypes/RoomDirectionMockups/screens`, with `css/home-tour.css` and the copy in `js/screen-tours.js`.

Phase 16b, the same day, added the other screens' tours, App tours on Profile (replay, the "Show tips on new screens" switch and Reset all tips) and the `.screenTour` modifier every screen uses; see [Every screen's tour](#every-screens-tour-phase-16b).

Phase 17 keeps the tours seen and the switch across launches, and Home's tour now starts as onboarding hands over; see [Kept across launches](#kept-across-launches-phase-17).

The Stage A audit (17 October 2026) added tours for the six screens that had none; see [The Stage A audit's six](#the-stage-a-audits-six).

## What's where

| File | Holds |
|---|---|
| `Models/Tours/TourProgress.swift` | `TourID`, `TourOutcome`, `TourRecord`, `TourProgress`, `TourRules` and the `TourProgressStore` protocol |
| `Models/Tours/TourRun.swift` | One tour while it shows: the step, Next, Back, and the record when it ends |
| `Fixtures/Stores/InMemoryTourProgressStore.swift` | The store in memory, for tests and previews |
| `Services/AppState/AppStateDefaults.swift` | `DefaultsTourProgressStore`, the app's store since Phase 17: seen versions and the switch in `UserDefaults`, records in memory |
| `DesignSystem/Components/Tour/` | `NookTourOverlay` (the dim, the spotlight, the tail and the card), `NookTourCard`, and `NookTourPlacement`, which decides where the card goes |
| `Features/Tours/TourCenter.swift` | Runs the tours: starting, the buttons, anchors, recording |
| `Features/Tours/TourAnchor.swift` | `.tourAnchor(_:label:hint:action:)`, `.tourFocusTarget(_:)` and `TourScrollReader` |
| `Features/Tours/TourOverlay.swift` | Draws the tour that's showing over the whole window |
| `Features/Tours/TourDefinition.swift`, `TourLaunchOptions.swift` | A tour's steps and words, and the `-tour` debug flag |
| `Features/Tours/ScreenTour.swift` | `.screenTour(_:isReady:)`, which starts a screen's tour when it may (16b) |
| `Features/Tours/TourCatalog.swift`, `TourText.swift` | What App tours lists, and the words every tour shares (16b) |
| `Features/Home/HomeTour.swift` | Home's four steps, in the words for each layout |
| `Features/*/…Tour.swift` | Each other screen's steps, next to the screen (16b) |
| `Features/Profile/AppToursSheet.swift` | App tours: the list, More screen tours, the switch and Reset all tips (16b) |

## How a screen gets a tour

1. Write its `TourDefinition`: a stable `TourID`, a content version, the steps (an anchor, a title and a sentence or two each) and the last button's words. Every layout of the screen shares the ID and the steps; only the words may differ.
2. Mark each control a step points at with `.tourAnchor(id, label:, hint:, action:)`. The label is what VoiceOver calls the control, the action is what a tap in the spotlight does (the control's own action). Each layout marks its own view with the same anchor. Mark the control VoiceOver should land on afterwards with `.tourFocusTarget(id)`. When the drawing to light up is bigger than the button (Home's furniture), anchor an invisible view the drawing's size and put the focus target on the button.
3. Wrap any scroll view the controls live in with `TourScrollReader`, so each one is scrolled into view as the tour reaches it.
4. Put `.screenTour(definition, isReady:)` on the screen's outermost view. `isReady` is true when the controls the tour points at are on screen and nothing is on top of them: no sheet, toast, alert or pushed screen, and no empty, loading or error state standing in for them. The modifier asks `TourCenter` when the screen appears, when `isReady` turns true, when another tour ends and when App tours asks for a replay, and passes a new layout's words on with `update` so the step stays.
5. Add the tour to `TourID.all`, `TourCatalog` and the `-tour` flag reads it from there.

The root view keeps one `TourCenter` for the app and draws the tour over the tab view, so the dim covers the bars and the tab bar can't be tapped through it. `TourCenter` lives above the part of the root that Delete my data rebuilds.

## When a tour starts

By itself, once a session, when tips are on and she hasn't seen this version (`TourRules.startsAutomatically`), and never while another tour shows. Finished, skipped and "tapped the highlighted control" all count as seen. A version goes up only when the controls or the steps really change, never for copy fixes. A store that can't be read means no tour (tours are optional), and a write that fails only means the tour may show again next launch.

Home's starts the first time Home shows, after its model has loaded, and never over a pushed screen, a sheet or a toast. Each other screen's rules are in the table below. After Delete my data the app goes back to onboarding (Phase 17), and the tour starts when she reaches Home again, as on a fresh install: Delete my data erases the tour progress with the profile and turns tips back on.

Since Phase 17 the versions seen and the switch are kept across launches, so a tour seen once doesn't come back after a relaunch (AC-103). Phase 21a moves them into the real preferences store.

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

- `-tour home`: start Home's tour when Home first shows, whatever is recorded. Any tour's ID works the same way (`-tour closet`, `-tour yourLooks`; the IDs are in `TourID.all`).
- `-tour reset`: forget the tours seen and turn tips back on, before anything starts.
- `-tour off`: turn tips off, so no tour starts by itself. Every UI test passes this except the tour's own.

Since Phase 17 both write to the state kept across launches, so `-tour off` lasts until a `-tour reset` or Delete my data. Every launch in the UI tests says what it needs.

For example `-fixtures demo -tour reset,home`. `scripts/check-release.sh` checks the flag isn't in a Release build.

## Tests

- `TourTests` (Models): stepping through a run, Back, the record, and when a tour may start.
- `TourStoreTests` (Fixtures): the store, every set starting fresh, and failing with the other stores. `DataDeletionFixtureTests` checks Delete my data resets it.
- `TourPlacementTests` (DesignSystem): below, above, beside, alone, and in the middle with no control; the card's width; what VoiceOver reads.
- `TourCenterTests` (Features): starting once, the buttons, what each way out records, tips off, a store that fails, the screen not ready, the debug flag, a new layout keeping the step, anchors and their owners, and a control out of sight getting no spotlight.
- `HomeTourSnapshotTests`: each of the four steps on iPhone 17, a step in dark, AX5, and the wide room on the 11-inch iPad sideways. `ComponentSnapshotTests` adds the catalog's "Quick tour card" page (`-catalog-page tour`).
- `HomeTourTests` (UI): completing the tour with Back on the way, skipping it, tapping the highlighted control, the tour being modal (the card's words first, nothing under the dim can be tapped), the tour at AX5, and the debug flag. `SettingsTests` checks the tour starts again after Delete my data and onboarding.
- `IPadTests` (UI): the spotlight follows the wardrobe through rotation and a narrow window, keeping the step.

### Needs a check with VoiceOver on

UI tests can't run VoiceOver, and on the iOS 26.5 simulator `typeKey(.escape)` reached neither Skip's `.keyboardShortcut(.cancelAction)` nor a focused `.onKeyPress(.escape)`, as 15b found for its shortcuts. On a device (an iPad with a keyboard for Escape) with VoiceOver on: focus lands on the card's words on each step; Escape and the two-finger scrub skip; activating the highlighted control opens it; nothing under the dim can be reached; and focus lands on that step's control when the tour closes.

## Decisions for Jose

1. **The card is opaque.** The mockup's card is 94% white over a 14-point blur. Without the blur the room's words showed through the card, so it's the plate colour, solid. The dim, glow and corners follow the mockup in warm tones.
2. **VoiceOver starts on the card's words, not on Next** (see above).
3. **Back was added**, from step 2, as a small chevron. The mockup has only Skip and Next.
4. **The tab bar is dimmed and covered too**, so nothing can be tapped through the tour. The card can sit over the tab bar when that's the only room left (the wardrobe step on iPhone).
5. **The last Home step says "You can replay this tour from it any time."** Since 16b that's true: App tours is on Profile, so the words stayed as approved.
6. **Delete my data names the tours** since 16b: "Name on your sign, Preferences, fit, measurements, try-on photo and the app tours you've seen".
7. **At the largest text sizes the card usually shows without a spotlight**, because a card that tall can't sit clear of a row. The words still say what the step is about, and the page behind has scrolled to the row.

## Every screen's tour (Phase 16b)

Spec: PRD §7.8, FR-73 and AC-103 ("every shipped user-facing screen"), the amendment's 16b items (LR-08, LR-13 and LR-18 wording, LR-02 colours) and Lily's sign-off. Copy comes from `js/screen-tours.js`; where the mockups are older than the sign-off, the words follow the amendment (see [Copy changed from the mockups](#copy-changed-from-the-mockups)).

Every screen that has a tour page in the mockups and exists in the app has a tour. The mockup's other tours are for screens the app doesn't have yet (Styling access, Subscription, Picture packs, Demo controls, Ask stylist, Ask another stylist, Find One, Purchase review, Visiting a shop, Saved products, Welcome) and come with their phases. Recently deleted, All suitcases, Delete my data, Accessibility, the Try it on sheet and editing a piece had no tour in the mockups, so 16b left them out; the Stage A audit added them (below).

| Tour (`TourID`) | Steps | Starts when |
|---|---|---|
| Closet (`closet`) | Add a piece, search, the filters; on a wide iPad the last step is the piece beside the grid | Her pieces are on screen (not empty, loading or failed), no toast |
| A piece of clothing (`garment`) | Edit, Style with this, Add to a suitcase | The piece has loaded and is in her closet, no sheet or toast |
| Add a piece (`addPiece`) | The three photo choices, Describe in words | On the first step of a new piece only; not on Edit |
| Style Me (`styleMe`) | Source, Occasion, Style me | The request is on screen, the closet isn't empty, no sheet (from the calendar it waits for the Occasion sheet) |
| Your looks (`yourLooks`) | The versions, Save look, Try it on, Swap a piece | The looks are ready on Today with no problem, sheet or toast. One version only: three steps |
| Swap a piece (`swap`) | Which piece, the options, Use this, Remove this piece | No See all or Find one sheet |
| Make your own look (`lookBuilder`) | Add a piece, the name, Save look | Her closet has loaded, no picker or toast |
| Saved Looks (`savedLooks`) | Her first look, Looks and Pictures, search | Looks tab with saved looks, no toast |
| A saved look (`look`) | Wear today, Swap a piece, Rename | Loaded, nothing open over it |
| Try-on picture (`picture`) | See the look, Delete picture | Loaded and its look still saved |
| Suitcases (`suitcases`) | + Add a suitcase, her first favourite | She has a favourite, no sheet or toast |
| Inside your suitcase (`suitcase`) | Name and picture, packing, Style me from this suitcase | Not archived, no sheet. An empty one has the first two steps; a new one waits for its packing sheet |
| Laundry (`laundry`) | The scope chips (only with a suitcase source), Mark clean, Mark all clean | Tracking on with pieces in the wash, no sheet or toast |
| Laundry is off (`laundryOff`) | Turn on, the link to Profile | Tracking off |
| Profile (`profile`) | Name on your sign, Fit and measurements, App tours | Loaded, no sheet, pushed screen or toast |
| Fit and measurements (`fit`) | Usual fit, the units, Weight, Add a piece that fits you well | Loaded, no sheet or toast |
| Help (`help`) | The first question, Still stuck? | Always |
| Send feedback (`feedback`) | Her note, Send privately | While she's writing (not sharing or sent) |
| Privacy and terms (`privacy`) | "Later, sent only if you allow it", Delete my data | No pushed screen or Safari view |

Every tour starts at version 1 and ends with Got it. A step about one item of a list points at the first one (her first look, the first piece in the wash, her first favourite suitcase, the first Help question, the Weight row), with `.tourAnchor(_:label:isEnabled:)` on each item so the list's views don't change.

**Only one at a time.** A screen asks while another tour shows and is turned away; it asks again when that tour ends. On a phone only one screen is on show, so that never happens; on a wide iPad, Closet's tour can be followed by the piece's beside it when both are new. Tapping a highlighted control ends the tour first, then does what the control does.

**Never over something.** Each screen's `isReady` lists what it holds back for. A toast holds a tour back too, so VoiceOver says the toast first.

### App tours

The row is on Profile under Help, as in `settings.html` ("Replay the tips for any screen"). It opens a sheet:

- Home, Closet, Style Me, Your looks, Saved Looks, Suitcases and Fit and measurements, each with "N quick tips" and a few words on what they cover (PRD §7.8). The rest are under **More screen tours**, which opens in place. Laundry's row is the one for the way tracking is set.
- **Show tips on new screens**, a switch with "Each tour shows once. Skip ends it." A line under the buttons says what happened ("You'll see tips the first time you open a screen." or "No more tips. You can replay any tour here."), and VoiceOver reads it.
- **Reset all tips**, which forgets every tour seen, so each shows again the next time its screen opens while tips are on. The switch stays as it was.

Choosing a screen closes the sheet, then opens that screen and starts its tour from step 1, whatever is recorded and even with tips off (`TourCenter.replay`). Profile's own screens (Fit, Help, Send feedback, Privacy and terms) are pushed on Profile; the root view opens the rest on their tab (`OpenForTourAction`): Home's room, Style Me on Home, Closet, Add a piece, Suitcases, Laundry, Saved Looks or Make your own look. A screen about one thing opens on the first one: the first piece in Closet, her first look, picture or favourite suitcase; with none yet it opens the screen before it, and the tour starts once she opens one. Your looks and Swap a piece need her to do something first (a Style Me request, which App tours never sends; a look to swap in), so they open Style Me and her first look, and the tour starts when she gets there. Their rows' VoiceOver hints say so.

Opening App tours holds Profile's own tour back for the session, so turning tips on or Reset all tips there doesn't start it the moment the sheet closes. Replaying it still does.

Home's navigation path moved to the root view (`homePath`), like Closet's and Saved Looks', so App tours can go back to the room or open Style Me.

### Copy changed from the mockups

The words are the mockups' except these, which follow Lily's sign-off and the amendment:

| Tour, step | Mockup | App |
|---|---|---|
| Your looks, 1 | "Fancy another look?" Shuffle shows other outfit ideas from your earlier looks. | "Three versions" Simple, Dressed up and Something new are the same outfit, styled three ways. Tap one to see it. (LR-05a, no Shuffle) |
| Your looks, 3 | Try it on shows an example picture here. It is a preview, so it cannot tell you how the clothes will fit. | Try it on makes a simulated picture of this outfit. It shows the style, not the exact fit. (RD-06, LR-12 line) |
| Your looks on iPad | Its own three steps with Shuffle | The same four steps as the phone, one tour ID |
| Swap a piece, 2 | Tap a piece you like from the choices below. | Tap a piece you like from these choices. (the spotlight is on them) |
| Swap a piece, 4 | (none) | "Don't need it?" Remove this piece takes it out of the outfit. You can undo it. (LR-08) |
| Outfit editor | "Outfit editor": name, rows, Save; "Tap a row to choose or change that part of your outfit." "You can come back and change it later." | "Make your own look": "Choose your pieces" Build an outfit yourself, piece by piece. Tap Add a piece to pick from your closet. Then the name, then "Tap Save look when it feels right. You can change a piece later with Swap a piece." (LR-08) |
| A saved look, 1 | Tap Wear to mark this outfit as worn. | Tap Wear today to mark this outfit as worn today. (LR-10) |
| A saved look, 2 | Tap Edit to change the pieces or the name. | Tap Swap a piece to change one piece. The rest of the outfit stays. (LR-08: no editor from a saved look) |
| A saved look, 3 | "A special favourite" Tap the star to mark a favourite. | "Give it a name" Tap Rename to change what this outfit is called. (no favourites in Stage A) |
| Try-on picture, 1 | This link opens the outfit behind the picture. | Tap See the look to open the outfit behind the picture. |
| Try-on picture, 2 | "Keep a favourite" Tap the star to mark a favourite picture. | "Tidy up" Tap Delete picture to remove one you don't want. You can undo it. |
| Saved Looks, 2 | Pictures keeps your saved try-on previews. | Pictures keeps your saved try-on pictures. |
| Add a piece, 1 | …These buttons use an example photo in this preview. | …For now each one adds a sample picture. |
| Suitcases, 2 | Open a suitcase to see what is packed and choose it for Style Me. | Tap a suitcase to choose it for Style Me, or its arrow to see what's packed. (a row chooses, the arrow opens) |
| Laundry is off, 2 | Tap Not now if you would rather keep things simple. | Leave it off if you would rather keep things simple. You can turn it on later in Profile. (no Not now on this screen) |
| Fit, 1 | Choose the fit that feels best to you. | …It's saved until you change it. (LR-18) |
| Fit, 3 | It starts at 130 lb in this preview. Tap Edit to change it, or clear it if you prefer. | Tap Weight to add it, or leave it blank if you prefer. |
| Fit, 4 | (none) | "Add a piece that fits you well" Pick something you own that fits just right. We'll use its brand and size to suggest sizes for you. (LR-13) |
| Help, 2 | This opens the example feedback form so you can see how asking for help would work. | Still stuck? opens Send feedback, where you can write a private note about the app. |
| Send feedback, 2 | "See how sending works" This form is pretend and sends nothing… | "Sending your note" Send privately opens the share sheet. You choose where your note goes, like Messages or Mail. |
| Privacy, 1 | These switches show the choices you would have before using styling features. | (on "Later, sent only if you allow it") Nothing here is sent yet. Later, each of these asks you first. |
| Privacy, 2 | This is where you would ask for a copy of your information. It is an example in this preview. | (on Delete my data) Delete my data erases everything the app keeps about you. It asks you first. |
| App tours names | Style Me request, Outfit editor, A saved outfit, Add or edit a piece, Profile and settings | Style Me, Make your own look, A saved look, Add a piece, Profile |

App tours' short descriptions are new: the mockup lists only the tip count, and the PRD asks for a short description.

### Tests (16b)

- `ScreenToursTests` (Features): every tour has two to four steps with their own controls, the words follow the approved changes, App tours lists every tour once with its tip count, first use once per screen and across a relaunch, never two at once, tips off, the `-tour` flag applied before any screen reads the store, replay (waits for its screen, even with tips off, once), Reset all tips, Profile held back while App tours is open, a failing store, and Delete my data forgetting a waiting replay. `TourTests` and `TourStoreTests` cover `forgetSeen`.
- `ScreenTourSnapshotTests`: one key step of each tour over its page on the iPhone 17 with the spotlight where the page's anchor is (read from `TourAnchorBounds`), Your looks in dark, Closet and Profile at AX5, Your looks and Fit on the 11-inch iPad, and the App tours sheet.
- `ScreenToursTests` (UI): on a fresh install (`-tour reset`) Home, Closet, a piece, Suitcases, Laundry, Saved Looks, a look, Swap a piece, Style Me and Your looks each show their tour once; with tips off nothing starts, App tours replays Closet, Profile and Help from step 1, tips on starts a new screen's tour, and Reset all tips shows a seen one again. It runs in CI's `ui-add-and-variants` part.

### Decisions for Jose (16b)

1. **Tours for the 19 screens the app has** that have a mockup tour; none for screens without one.
2. **In Stage A every launch was a fresh install for tours too.** Phase 17 fixed it: the tours seen and the switch are kept across launches (see below).
3. **Replay opens the first item** (piece, look, picture, suitcase) for the screens about one thing, and Your looks and Swap a piece start when she next gets there.
4. **Laundry's two tours are separate** (on and off), as in the mockups, and App tours lists the one that matches tracking.
5. **On a wide iPad two new screens can show their tours one after the other** (Closet, then the piece beside it), never together.
6. **Profile's own tour doesn't start as App tours closes**, even after tips on or Reset all tips. It waits for the next session or a replay.
7. **App tours' descriptions are new copy** (see above).

## Kept across launches (Phase 17)

16b noted that Lily's TestFlight build would show every tour again after each relaunch. Phase 17 splits `TourProgress`:

- **`seenVersions`**, the latest content version seen of each tour, and **`showsTipsOnNewScreens`** are app state in the lowest tier of `closet/DATA_MAP.md`: they name only the app's own screens. `DefaultsTourProgressStore` keeps them in the app's `UserDefaults` suite (`docs/onboarding.md`). `TourRules.startsAutomatically` reads `seenVersions`, so a version seen in an earlier session counts.
- **`records`**, how each tour ended and when, are Personal in the data map and stay in memory for the session.

Reset all tips clears both and keeps the switch; Delete my data and `-tour reset` clear everything. A value that can't be read counts as not seen, so a tour can show again but never gets stuck hidden.

Home's tour starts when Home first shows after onboarding, as on any first visit: the root keeps the `TourCenter` above both onboarding and the tabs. `OnboardingTests` (UI) goes through onboarding to Home's tour and Style Me's, then relaunches and checks neither comes back.

## The Stage A audit's six

Jose's Stage A audit decision 3: short tours for the six screens without one, in the same style. The mockups have no tour pages for them, so the words are new, written to the amendment's rules (PRD §7.8): two or three steps on real controls, one or two plain sentences each, Got it at the end, version 1.

| Tour (`TourID`) | Steps | Starts when |
|---|---|---|
| Recently deleted (`recentlyDeleted`) | "Kept for 30 days" on the first piece, "Changed your mind?" on its Restore | A deleted piece is listed, no toast |
| All suitcases (`allSuitcases`) | "Find a suitcase" on search, "Put away, not gone" on the Archived filter (only when she has archived suitcases), "Back to everything" on Main closet | Loaded, no sheet or toast |
| Delete my data (`deleteData`) | "What goes" on the list, "It asks once more" on the button | The counts are read, not asking or deleting, nothing left from a failed deletion |
| Accessibility (`accessibility`) | "It follows your iPhone" on the settings, "Change them in Settings" on Open Settings | Always |
| Try it on (`tryOn`) | "A simulated picture" on what it makes, "Only when you ask" on Make a picture | The sheet is on its first step (nothing made, no picture she already has) |
| Editing a piece (`editPiece`) | "The picture" on the photo button, "Fix any detail" on the name, "Keep your changes" on Save in the bar | Editing a piece she has, not the draft card, no question or photo choice open |

Tapping a highlighted control does what it does, as on every tour: Restore restores, Open Settings opens Settings, Make a picture makes it, Save saves, Delete my data asks once more.

**A tour on a sheet.** Try it on is a sheet, and a sheet covers everything the root draws, including the tour. So `TourDefinition.isInSheet` marks it, the root's overlay leaves it out, and every styled sheet draws an overlay of its own (`nookSheetOverlay`, set by `RootTabView`) that draws only tours on sheets. The tabs stay readable to VoiceOver underneath, since the sheet covers them and the tour is modal on it.

**App tours.** All six are under More screen tours. Accessibility and Delete my data open on Profile. Recently deleted opens on Closet, All suitcases on Closet with Suitcases under it, and editing a piece opens her first piece in Edit. Try it on opens her first saved look, and the tour shows when she taps Try it on ("Opens your first saved look. Shows when you tap Try it on.").

**Tests.** `ScreenToursTests` (Features) has the six in every check (two to four steps on their own controls, Got it, the catalog's tip counts) and checks only Try it on is on a sheet. `ScreenTourSnapshotTests` adds one key step of each: Restore, the Archived filter, Delete my data's button, Open Settings, Make a picture on the sheet, and the name while editing (Save is in the bar, which the still image doesn't draw). The UI walk `testFreshInstallShowsEachTourOnce` visits all six, including the Try it on tour through to Got it with Make a picture tappable afterwards, and `testReplayFromProfileAndTipsOff` replays Delete my data.
