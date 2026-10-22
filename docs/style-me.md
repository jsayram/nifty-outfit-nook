# Style Me request

Phase 10a, 14 October 2026. Style Me is the screen the desk laptop opens (RD-02): one calm column with the request, the options for this request, and one Style me button. Phase 10a builds the request; Your looks, the results, came in 10b (`docs/your-looks.md`).

Spec: amendment RD-02, LR-03 (Preferences), LR-04 (Weather), LR-18 (the Comfort line), decision 2 (Style with this); PRD §8.1 (sources and strict suitcases), §8.3 (today's comfort and colour), FR-03, FR-05, FR-48 and FR-67. The visual reference is `styleme.html` in `closet/prototypes/RoomDirectionMockups/screens`, with Lily's sign-off sheet where they differ ("Preferences", not "Mode"; the Weather row).

## What's where

| File | Holds |
|---|---|
| `Models/Styling/StyleRequestBuilder.swift` | `StyleRequestDraft` (her choices so far), `StyleRequestIssue`, `StyleRequestCheck` and `StyleRequestBuilder`, which checks a draft and builds the `StyleRequest` |
| `Models/Styling/ColorWish.swift` | A colour wish: family, preferred or required, and where (PRD §8.3) |
| `Features/StyleMe/StyleMeModel.swift` | Loads the closet, suitcases, profile and weather; holds the draft and re-checks it on every change |
| `Features/StyleMe/StyleMeText.swift` | Every value, line and notice on the screen, and the words for Comfort, Preferences and colour wishes |
| `Features/StyleMe/StyleMePage.swift` | The page: request cards, option rows, notices and the Style me button |
| `Features/StyleMe/StyleMeSheets.swift` | The sheets: Source, Occasion, Starting piece, Comfort, Colour, Preferences |
| `Features/StyleMe/StyleMeScreen.swift` | Navigation, the sheets and Style me |
| `Features/StyleMe/WeatherRow.swift`, `WeatherRowContent.swift` | The Weather row and its sheet, from Phase 5a, unchanged |

## The screen

Top to bottom, as in `styleme.html`:

- **Your request.** Source (Main closet with its piece count, or a suitcase with "5 pieces · Suitcase only"), Occasion (on butter, as on the calendar) and Starting piece (the piece's picture once she has one). Each is a soft card with a chevron.
- **Options, for this request only.** Weather (LR-04, 5a's row and sheet), Comfort with "Just for this outfit." under it, or "Today: fitted (you usually like relaxed)" when today differs from her usual fit (LR-18), Colour, and Preferences (LR-03).
- **Style me**, with "Uses 1 styling request." under it.

Every row shows its current value and opens its own small sheet (RD-02.2). Single choices close the sheet; the Colour sheet and Other's words stay open until Close. Changing one sheet never touches another choice.

| Sheet | What it offers |
|---|---|
| Source | Main closet, then her active suitcases by name, each with its piece count. The choice is remembered for next time (Phase 13, FR-67) |
| Occasion | The FR-03 chips: Office, Date night, Brunch, Concert, Casual, Event, Other. Other asks "What's the occasion?" in up to 40 characters, kept with this request only |
| Starting piece | No starting piece, then the pieces in the source that can be used today, with search. A piece that can't be used isn't offered |
| Today's comfort | Usual fit (named, "Usual fit (Relaxed)"), Fitted, Comfortable, Relaxed |
| Colour | Any or a colour family, then How strongly (Preferred, Required) and Applies to (Any one piece, Top, Bottom, Dress, Layer, Shoes, Overall palette), with a sentence saying what it means. Strength and place wait until a colour is picked |
| Preferences | Exactly the two values, Mine + one idea and Only mine (LR-03.2). From a suitcase both are dimmed under a "Suitcase only" note with Style from Main closet (LR-05b) |

The defaults are good enough to tap Style me straight away (RD-02.3): the source and occasion she chose last (Main closet and Office on a fresh install, Phase 13), no starting piece, today's weather, her usual fit, any colour, and her saved Preferences (Mine + one idea for Lily, LR-03.3).

**Request scope.** The draft lives as long as the screen. Coming back from a pushed screen (Add a piece, the results) reloads the closet and keeps every choice. A new Style Me starts on the defaults again, so Comfort, Colour and Weather reset (RD-02.4, LR-04.2, LR-18.2), Preferences starts from her saved choice, and the source and occasion start from the ones she chose last (Phase 13).

**Where it opens from.** The laptop opens it. The calendar opens it on the Occasion sheet. A garment's Style with this, then Style me with it, opens it with that piece as the starting piece (decision 2).

## Checking a request

`StyleRequestBuilder` is a pure rule in Models: it takes the garments, suitcases, her saved preferences and the date, and checks a draft. The checks are ownership and availability facts (`Eligibility`) and counts, never styling taste. The screen re-checks on every change. Some issues stop Style me; the rest are early warnings.

| Issue | Stops Style me | What the screen says |
|---|---|---|
| Closet empty | Yes | The whole page becomes "Your closet is empty" with Add a piece |
| Suitcase missing or archived | Yes | "This suitcase isn't there any more" with Choose another source. It never quietly becomes the main closet (FR-67) |
| Suitcase empty | Yes | "Spring trip is empty", with Add pieces (Suitcases) and Choose another source. Nothing is invented for an empty suitcase (§8.1) |
| Fewer than 2 usable pieces | Yes | "Only 1 of 2 pieces in Beach can be used today. A look needs at least 2." Pieces in the wash (while tracking) or away don't count |
| A suitcase with 2 to 5 usable pieces | No | "Jose's house has 5 pieces you can use today, so you may get fewer than three versions." |
| Starting piece unusable | Yes | On the card ("In the wash", "Not packed in Weekend", "Away right now"), and a note with Choose another and No starting piece |
| Other's words too long or on two lines | Yes | Under the field. The field also stops at 40 characters |
| A required colour no usable piece has | No | "No navy shoes in Weekend can be used today." with Make it preferred |

The few-pieces warning starts below 6 usable pieces: a base outfit plus a dressier piece and another piece to swap in. It's a heads-up, not a rule; the stylist decides what it can make (10b shows partial and insufficient results honestly).

Weather that can't be read isn't an issue: the Weather row says so and Style me still works (LR-04.3).

**Building.** `build(_:weather:id:createdAt:)` returns the `StyleRequest` or throws `cannotStyle` with the blocking issues. Today's weather goes in only with Use today's weather, so an indoors request carries none. Other's words are trimmed, and dropped for any other occasion. The piece mode comes from the draft; laundry tracking and the repeat window come from her saved preferences. A unit test runs 2,688 combinations (sources, starting pieces, Preferences, laundry, colour wishes and weather choices) and checks that Style me is allowed exactly when a request is built, that every built request passes `StylingContext.make`, and that a new-piece idea is only allowed from the main closet with Mine + one idea.

## Style me

Opening Style Me sends nothing; only the button does (RD-02.1). The button builds the request and opens Your looks, which sends it (`docs/your-looks.md`). Coming back keeps every choice, and Your looks can send her back with the source set to Main closet. In 10a the button opened a stand-in that showed the request in words and as JSON; 10b replaced it. The request is never logged, since it can hold today's comfort (Sensitive). It holds IDs, not names: no suitcase name, piece name or sign name goes into it (DATA_MAP.md, `StyleMeModelTests.theRequestHoldsNoNames`).

## Accessibility

- Each request card is one button, read as it looks ("Source: Weekend, 8 pieces · Suitcase only", "Starting piece: Navy dress pants, Your looks are built around it") with a hint. Option rows read their title, line and value.
- Sheet choices have the selected trait as well as the check mark or solid pill, so the choice isn't shown by colour alone.
- Notices are read as one element, then their buttons. A disabled Style me says why in its hint.
- At the accessibility sizes the cards and rows put their icon above the words, the chips wrap, sheets open full height and Close sits above the sheet's title (a DesignSystem change in this phase, so "Preferences" doesn't break mid-word).
- Dark appearance uses the tokens throughout. No animation of its own, so Reduce Motion has nothing to change.

## Tests

- `StyleRequestBuilderTests` and `StyleRequestDraftTests` (Models): the defaults, every option carried, weather choices, Other's words, sources of every size, every reason a starting piece can't be used, colour wishes by place, and the combinations test.
- `StyleMeModelTests`: loading the demo, nothing sent until Style me (a counting stylist), every choice in the request, Style with this, a starting piece in the wash or outside the suitcase, each suitcase state, the empty closet, unreadable weather, a store failure, request scope, Preferences from her profile, and checking the large closet quickly.
- `StyleMeSnapshotTests`: the default request in light, dark and AX5; every choice set; the empty closet, empty suitcase, small suitcase with problems, unreadable weather (dark) and error states; each sheet, the Colour sheet in dark, two sheets at AX5; the stand-in results.
- `StyleMeTests` (UI): set every option from the laptop and check the results; the calendar's Occasion sheet with Other's words; an empty suitcase; the empty closet's Add a piece; Style with this into the request. `GarmentDetailTests` checks a piece in the wash can't start a look.

## Decisions for Jose

1. **An empty main closet can't style.** PRD §8.1 allows clearly labelled hypothetical ideas with zero inventory. Stage A's mock stylist and `ResultCheck` need an owned Simple, so for now the empty closet offers Add a piece instead. Still open after 27a: the cloud stylist keeps the same rule until Jose decides.
2. **The occasion and source are remembered** since Phase 13: Style Me starts from the ones she chose last (`Profile.remembered`), and Other isn't remembered. A remembered suitcase that's gone still shows "This suitcase isn't there any more", so nothing styles from everything without her choosing it.
3. **Preferences on Style Me is for this request.** It starts from her saved choice each time; changing the saved one is Profile's job (14a). FR-05 asks to keep "refine this request" and "update a usual preference" apart.
4. **"Colour", not "Color"**, to match the rest of the app (Closet's filters, Add a piece). The amendment writes Color.
5. **A Dress place for colour.** The mockup's Applies to has no Dress; the closet has dresses, so it's there.
6. **The few-pieces warning starts below 6 usable pieces** in a suitcase. The main closet only stops below 2.
7. **No offline banner on the request.** The fixture `offline` behaviour fails the stylist, which 10b shows on Your looks. Everything on this screen works offline.

## Left for later phases

- **10b (done):** Your looks replaced the stand-in. It calls the stylist with `StylingContext.make`, marks the suitcase as used, and shows partial, insufficient, failed and offline results.
- **13 (done):** remembering the source (FR-67) and the occasion, Add pieces opening the real suitcase, and "Style me from this suitcase" (`docs/suitcases-and-laundry.md`).
- **14a (done):** her usual fit and Preferences in Profile (`docs/profile.md`).
- **15b (done):** on a wide iPad the request sits beside the options (`docs/ipad.md`).
- **27a (done):** with the real services (or `-cloud-stylist` in debug builds) Style me goes to the cloud stylist, after her consent and a check of her history first ([decision 0008](decisions/0008-cloud-stylist.md)). The request screen is unchanged.
