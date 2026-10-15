# Models and the store protocol

Phase 3, 14 October 2026. This is the data layer every screen will sit on. Read it before the screens start depending on it: changing a type now is cheap, and later it isn't.

Sources: PRD §12 (core data model), the room-direction amendment's "Data model notes" and its LR and RD items, and `closet/DATA_MAP.md` for data tiers.

## Where things live

| Module | Holds | Depends on |
|---|---|---|
| `Models` | Value types, the rules as pure functions, and the service protocols | Foundation only |
| `Fixtures` | In-memory stores (actors), the mock stylist, and the empty, demo and large data sets | Models |
| `Features` | Screens. They read `NookServices` from the environment and only see protocols | DesignSystem, Models |
| App target | Reads `-fixtures`, builds `NookServices` from Fixtures, hands it to `RootTabView` | everything |

Models has no user-facing text. Enum cases are words like `.dateNight` or `.dressedUp`; the screens turn them into localized labels.

Every type is a `Sendable`, `Codable`, `Hashable` value. Records that have an identity are `Identifiable` with a typed ID (`Garment.ID`, `Look.ID` and so on). An ID is a string that never changes: readable in fixtures (`g-navy-trousers`), a UUID for anything made at run time. The types keep a garment ID and a look ID apart, so one can't be passed for the other.

## The types

**Garment** (Personal; `notes` is Sensitive). Her name for it, category (top, bottom, dress, layer, shoes, bag, accessory), colours (named families, main first, with her own words for the shade in `colorNote`), fit (fitted, regular, relaxed), dressiness (casual, smart, dressy), warmth, seasons, occasions, brand, size label, notes and a photo reference (none, sample art, or a stored photo later). Then the states, each separate because each changes for its own reason:

- `ownership`: owned, purchased (with arrival: not arrived, arrived, unknown), wishlisted, or no longer owned ("I don't have it any more", LR-16).
- `laundry`: clean or dirty. Only matters while Track laundry is on, and kept while it's off (RD-11).
- `availability`: available, or unavailable until a date (lent out, at the tailor).
- `isArchived`: in the data, but no Stage A screen (LR-16).
- `deletedAt`: in Recently deleted, purged 30 days later.
- `wornOn`: the days she chose Wear today, one entry per day. `lastWorn` comes from it (LR-10).

**GarmentDetails** (Personal; `notes` is Sensitive). The facts she types or picks on Add a piece and Edit (Phase 7b): everything above except the states. `GarmentDetails(garment)` reads them from a piece, `apply(to:)` writes them back without touching its states, and `makeGarment(id:addedAt:)` makes a new owned piece. The kind is optional here, so a new piece never gets one she didn't choose.

**GarmentDraft** (Sensitive, since it can hold her notes and her own words). An unsaved add or edit: its target (a new piece or a garment), the step she was on, the details, what they started from, her description, and when it was last written. See `docs/add-a-piece.md`.

**GarmentCutout** (Personal, Phase 8b). A garment's `cutout`: the cutout picture's reference and its `CutoutQuality`. `nil` until a cutout is made. A new photo on Edit drops it. See `docs/stickers.md`.

**Look** (Personal). Pieces, an optional name (set when saved), occasion, the source it was made from, `isSaved`, when it was saved (`savedAt`, Phase 12a, for "Saved 3 Oct" and Saved Looks' order), wear days, and a link to a try-on picture. A styling result is one base outfit in three versions (LR-05a), so each version is its own Look with a `version` (Simple, Dressed up, Something new) and a shared `resultID`. A look she built in Make your own look has neither. Unsaved results stay in the store as background history (LR-06).

A **LookPiece** is either a garment she owns (by ID) or a **PieceIdea**: a described piece she doesn't own, shown as "Not in your closet" with Find one. An idea never becomes owned by being in a look. Each piece records whether it's the same as in Simple ("Same as Simple", LR-05a.3).

**LookDraft** (Personal, Phase 11). A look she started in Make your own look and hasn't saved: her name for it so far, the source, the pieces, the starting piece, when it was written. One at a time, in `LookDraftStore`. See `docs/swap-and-editor.md`.

**Suitcase** (Personal). Name, icon (which drawing stands for it in the hall), the set of garment IDs it holds (it never copies a garment), `lastUsedAt`, archived, created. Favourites come from `lastUsedAt`.

**Profile**. The sign name (Personal, may be empty), Preferences (Personal), usual fit, liked and avoided colours, and three Sensitive groups: body measurements (all optional, each with its unit), "pieces that fit you well" (LR-13), and the try-on photo. The doc comment on each field names its tier.

**Preferences**: piece mode (Mine + one idea by default, or Only mine), repeat window (1 week by default, 2 weeks, I don't mind), Track laundry (off by default). These are Lily's defaults from the amendment (LR-03, LR-10, RD-11).

**StyleRequest** (Sensitive when it carries today's comfort). Source, occasion (with her words for Other, at most 40 characters), weather choice (use today's, indoors, ignore) with the weather snapshot, today's comfort, a colour wish (`ColorWish`: a family, preferred or required, and where: any one piece, a kind of piece, or the overall palette), a copy of Preferences, and the starting piece. Style Me builds it from a `StyleRequestDraft` with `StyleRequestBuilder` (Phase 10a, `docs/style-me.md`). `allowsNewPieceIdea` is computed, not stored: true only with Mine + one idea and the main closet, so a suitcase request can never ask for an unowned piece.

**Results.** The stylist returns a `StyleOutcome`:

- `complete(StyleResult)`: all three versions;
- `partial(StyleResult, missing:)`: one or two versions, each missing one with a reason (no dressier piece, no other owned piece);
- `insufficient(InsufficientWardrobe)`: no valid outfit, with the kinds of piece that are missing.

A `StyleResult` has the versions, ranked owned alternatives per piece (for Swap and Show 3 more), and quiet notes ("You wore this last week", "Something new stays owned in a suitcase", "weather unavailable", and since 10b a required colour nothing could meet, and "every outfit has been shown"). A failure to finish is not an outcome: the stylist throws `StylistError` (not completed, offline, timed out, cancelled), so a model or network problem can never be shown as "your closet is too small".

## The rules

Pure functions in `Models/Rules`, each with unit tests. Stores and screens both call them; no rule lives inside a store.

| Rule | What it decides | Spec |
|---|---|---|
| `Eligibility` | Which pieces may be styled: owned or arrived, not deleted, archived or unavailable, not dirty while tracking, and inside the suitcase | PRD §8.1, RD-11.2, LR-12.1 |
| `StylingContext.make` | Builds what the stylist gets: the request, eligible pieces from the source, main-piece combinations worn inside the repeat window, and (since 10b) those already shown for this request, so Try a different outfit gets a new base. Rejects a missing or archived suitcase and an unusable starting piece | PRD §8.1, LR-10, LR-05a.4 |
| `WearRules` | Calendar-day wear windows (1 week = today and the 6 days before), one wear per day, Undo, and recent main-piece combinations (tops, bottoms, dresses; shoes and single favourites can repeat) | LR-10 |
| `ResultCheck` | Checks a result before it's shown: Simple present, 2 to 6 pieces, only eligible pieces, ideas only in Something new and only when allowed, at most one, the starting piece in every version, every version shares a piece with Simple, "Same as Simple" marks right | PRD §8, LR-05a, LR-05b |
| `SuitcaseShelf` | Three favourites by most recent use, See all only above three, archived only under their filter | RD-09, LR-17 |
| `HamperState` | Off, all clean, or "2 to wash" | RD-11 |
| `GarmentFilter` | Piece chips, colour swatches, the Suitcase filter, the Dirty chip and typed search, all combined. Every typed word must match the name, brand, colour note, a suitcase name, or an extra word the screen passes in (Closet passes its names for the piece's kind and colours) | LR-09, LR-11, RD-11 |
| `StyleRequestBuilder` | Checks a Style Me draft before it's sent: an empty closet or suitcase, a missing suitcase, too few usable pieces (stops it), a small suitcase (warns), a starting piece that can't be used, Other's words, a required colour nothing usable has (warns). Builds the request | RD-02, FR-67, PRD §8.1, §8.3 |
| `LookFilter` | Saved Looks' piece chips, colour swatches and typed search. A chip and a swatch match one piece together ("black bottoms"); every typed word must match the look's name, a piece's name, or the screen's words for the occasion, kinds and colours | RD-08, LR-09 |
| `GarmentRules` | The Add a piece form: a name and a kind required, length limits on the shade, brand, size and notes, one-line fields. Every problem at once, by field. Stores run it on every garment save | Phase 7b |
| `CutoutThresholds` | Whether a cutout's signals are clean enough for a sticker. `current` is 8a's proposal until the benchmark on her phone | RD-07, Phase 8a |
| `GarmentArtChoice` | How a piece's picture shows: its drawing (no photo), its cutout (clean), or its photo in a tile (no cutout yet, or a concern) | RD-07, Phase 8b |
| `SwapRanking` | Swap a piece's options: her pieces of the same kind she can wear from the look's source, good matches (occasion, weather, colours that sit with the rest) best first, weaker ones and outfits worn lately set aside for See all | LR-07, LR-10, Phase 11 |
| `LookEditing` | One piece replaced or removed, as a new look that keeps its version, occasion, source and other pieces | FR-09, LR-08 |
| `LookRules` | A hand-made or hand-changed look: 2 to 6 pieces, a dress or a top and a bottom, one of each kind in Make your own look, every piece wearable | RD-07.1, LR-08 |
| `EditHistory` | Undo and Redo of whole values, up to 20 | PRD §7.3, LR-08.2 |
| `NameRules`, `MeasurementRules` | Trimmed names with length limits, no control characters, unique suitcase names; measurement sanity ranges (they catch typos and say nothing about fit) | RD-03.2, LR-13 |

## The store protocol

Features talk only to these. Each is `Sendable` with `async` calls and typed errors (`StoreError`: not found, unavailable, cancelled, invalid name, invalid details, invalid measurements), so an actor, a database or a sync engine can sit behind it. Stage A has in-memory actors; Stage B puts persistence behind the same protocols (Phase 20a).

```swift
protocol ClosetStore: Sendable {
    func garments() async throws(StoreError) -> [Garment]          // everything, newest first
    func garment(_ id: Garment.ID) async throws(StoreError) -> Garment
    func save(_ garment: Garment) async throws(StoreError)          // add or replace; checks the name
    func update(_ id: Garment.ID, _ change: @Sendable (inout Garment) -> Void) async throws(StoreError) -> Garment
    func recordWear(of ids: [Garment.ID], on date: Date) async throws(StoreError)   // Wear today
    func removeWear(of ids: [Garment.ID], on date: Date) async throws(StoreError)   // Undo
    func setLaundry(_ state: LaundryState, for ids: [Garment.ID]) async throws(StoreError)
    func delete(_ id: Garment.ID, at date: Date) async throws(StoreError)           // to Recently deleted
    func restore(_ id: Garment.ID) async throws(StoreError)
    func purgeExpired(asOf date: Date) async throws(StoreError) -> [Garment.ID]
}

protocol LookStore: Sendable { looks, look, save, update, delete, recordWear, removeWear }
protocol SuitcaseStore: Sendable { suitcases, suitcase, create(name:icon:at:), update, add, remove, markUsed, delete }
protocol ProfileStore: Sendable { profile, save }   // save checks the sign name, measurements and fit pieces

protocol Stylist: Sendable {
    func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome
}
protocol WeatherProvider: Sendable { func currentWeather() async throws(WeatherError) -> WeatherSnapshot }
protocol ImageProvider: Sendable { func imageData(for: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? }

// Phase 7b, Add a piece
protocol DraftStore: Sendable { drafts, draft(for:), save, discard }      // unsaved adds and edits
protocol PhotoIntake: Sendable { func photo(from: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference }
protocol GarmentDescriptionReader: Sendable { func suggestions(for: String) async throws(DescriptionError) -> [GarmentSuggestion] }

// Phase 8a, cutouts
protocol CutoutService: Sendable { func cutout(from: Data) async throws(CutoutError) -> CutoutResult }

// Phase 11, Make your own look
protocol LookDraftStore: Sendable { draft, save, discard }      // the one unsaved look
```

`CutoutResult` is the subject as a PNG on transparency with `CutoutQuality` signals; `CutoutThresholds` (a rule) turns them into sticker or tile. Stage A's `NookServices.cutouts` is `StandInCutoutService`, which hands the photo back with the signals it was given. The Vision implementation lives in the `Services` module and is described in `docs/cutout-feasibility.md`.

`NookServices` bundles one of each. The app target builds it and passes it to `RootTabView`, which puts it in the SwiftUI environment (`\.services`). Screens never build services.

A store returns everything it holds and leaves filtering to the rules: Closet shows `isInCloset`, Saved Looks shows `isSaved`, Suitcases arranges with `SuitcaseShelf`. Wear today on a look is two calls (the look and its pieces); the screen does both, so neither store needs to know about the other.

## Fixtures

Pick a set with `-fixtures <set>`, and optionally options after colons: a behaviour (`-fixtures demo:offline`), `weather=<state>` and `laundry=<state>` (`-fixtures demo:weather=night:laundry=full`). The README lists every value. Unknown values fall back to `demo`, `normal` and the set's own weather and laundry.

| Set | Contents |
|---|---|
| `empty` | A fresh install: nothing, default preferences, empty sign name |
| `demo` | The prototype's 21 garments in the new model (every state: wishlist, bought not arrived, no longer owned, Recently deleted, archived, at the tailor, dirty, text-only, worn recently and long ago), six looks (including a saved Something new with an idea piece, one she made herself, and an unsaved result), six suitcases (one empty, one archived, five active so See all shows), and a profile named Lily. Weather: 58° and rain |
| `large` | 2,400 generated garments, 600 looks and 40 suitcases from a fixed seed, so every run is the same |

| Behaviour | What happens |
|---|---|
| `normal` | Everything answers at once |
| `slow` | Stores wait 0.6 s, weather 1 s, the stylist 3 s (loading states) |
| `offline` | The stylist throws `offline` and weather can't be read; local stores still work |
| `stylist-fails` | The stylist throws `notCompleted` |
| `stylist-partial` | The stylist returns Simple and Dressed up only |
| `stylist-insufficient` | The stylist says the source can't make a look (a bottom and shoes missing) |
| `stylist-waits` | The stylist never answers until cancelled, for Your looks' styling state |
| `offline-once` | The first styling request fails as offline and later ones work, as if the connection came back. Weather and stores work |
| `stores-fail` | Every store call throws `unavailable` (error states) |
| `photo-fails` | Add a piece's photo stand-in says the photo couldn't be read |

`photos=samples` adds eight pieces with drawn sample photos and stand-in cutouts, and an image provider (`SamplePhotoProvider`) that draws them, so stickers and tiles can be seen without real photos (Phase 8b, `docs/stickers.md`).

`draft=add` or `draft=edit` puts an unsaved draft in the draft store at launch, as if the app had been closed in the middle of Add a piece (the sage cardigan) or Edit (the navy dress pants renamed). `draft=look` puts a half-built Make your own look in the look draft store ("Pink for Friday": the pink shirt and the navy dress pants, Phase 11). Stage A drafts live in memory, so UI tests use it after a relaunch.

Add a piece's stand-ins: `InMemoryDraftStore`, `StandInPhotoIntake` (a sample picture for every source, no permission asked) and `WordMatchDescriptionReader` (Describe in words, a deterministic word matcher on the phone with no style rules).

Dates in the demo and large sets are relative to launch time, so "Last worn" reads naturally; tests pass a fixed date.

The **mock stylist** is deterministic and uses plain matching on stored facts only: occasion tags, season, warmth against the temperature, fit against comfort, and the colour wish where she asked for it (a required colour counts the same as a preferred one when matching; since 10b a result says when a required colour couldn't be met). It pairs the best-matching main pieces with shoes, adds a layer in rain or cool weather, skips main-piece combinations worn inside the repeat window, swaps in a dressier owned piece for Dressed up, and adds one idea (or swaps another owned piece) for Something new. For Try a different outfit it starts from a base not shown yet, and says so when every base has been shown. It has no real fit or styling rules; those stay in the private backend.

Performance, measured on an Apple-silicon Mac running the iOS 26.5 simulator in Debug: generating the large set 36 ms, five filters over it 35 ms, building a styling context 6 ms, styling 41 ms. The tests allow 1 s, 500 ms, 500 ms and 500 ms, so a failure means something got many times slower. Each check takes the fastest of three runs and allows three times as long on CI, after two checks went over once on a busy CI runner (a context build took 862 ms there, against 6 ms locally).

## Left out on purpose

- **Persistence, revisions and sync.** The PRD's revision numbers, deletion markers and sync conflicts arrive with real storage (Phases 20a to 21b). Adding them to in-memory fixtures now would be guesswork.
- **Favourites and collections** (PRD §8.2) have no Stage A screen (RD-08), so no type yet.
- **Find One, shopping and the fit check** (Phase 34). Wishlist pieces exist as an ownership state only.
- **More than one colour.** Since 10a the request has one colour wish, preferred or required, with its place (PRD §8.3). Several colours at once, or explicit monochrome, can come later if Lily asks.
- **Swap ranking on the server.** Phase 11 ranks swaps on the phone with `SwapRanking` (plain matching on stored facts). The stylist's own `alternates` aren't used by Swap yet; better ranking that needs the private rules would be a server call later.

## Decisions for Jose

1. **No body measurements in the demo profile.** The repo is public and DATA_MAP.md asks fixtures to stay synthetic, so Lily's real height isn't in it. Tests use made-up values.
2. **Comfort and fit share three words.** Today's Comfort (fitted, comfortable, relaxed) maps one to one onto a garment's cut (fitted, regular, relaxed). It's a word match, not a fit rule.
3. **A mock outfit needs shoes plus a dress, or a top and a bottom.** So the demo Gym suitcase (a tee and sneakers) comes back insufficient, missing a bottom. The real stylist will decide this for itself.
4. **Suitcase icon** is a fixed set of five drawings (rolling, duffel, weekender, backpack, tote). The art comes in Phase 13.
