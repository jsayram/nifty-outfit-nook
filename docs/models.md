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

**Look** (Personal). Pieces, an optional name (set when saved), occasion, the source it was made from, `isSaved`, wear days, and a link to a try-on picture. A styling result is one base outfit in three versions (LR-05a), so each version is its own Look with a `version` (Simple, Dressed up, Something new) and a shared `resultID`. A look she built in Make your own look has neither. Unsaved results stay in the store as background history (LR-06).

A **LookPiece** is either a garment she owns (by ID) or a **PieceIdea**: a described piece she doesn't own, shown as "Not in your closet" with Find one. An idea never becomes owned by being in a look. Each piece records whether it's the same as in Simple ("Same as Simple", LR-05a.3).

**Suitcase** (Personal). Name, icon (which drawing stands for it in the hall), the set of garment IDs it holds (it never copies a garment), `lastUsedAt`, archived, created. Favourites come from `lastUsedAt`.

**Profile**. The sign name (Personal, may be empty), Preferences (Personal), usual fit, liked and avoided colours, and three Sensitive groups: body measurements (all optional, each with its unit), "pieces that fit you well" (LR-13), and the try-on photo. The doc comment on each field names its tier.

**Preferences**: piece mode (Mine + one idea by default, or Only mine), repeat window (1 week by default, 2 weeks, I don't mind), Track laundry (off by default). These are Lily's defaults from the amendment (LR-03, LR-10, RD-11).

**StyleRequest** (Sensitive when it carries today's comfort). Source, occasion, weather choice (use today's, indoors, ignore) with the weather snapshot, today's comfort, a colour wish, a copy of Preferences, and the starting piece. `allowsNewPieceIdea` is computed, not stored: true only with Mine + one idea and the main closet, so a suitcase request can never ask for an unowned piece.

**Results.** The stylist returns a `StyleOutcome`:

- `complete(StyleResult)`: all three versions;
- `partial(StyleResult, missing:)`: one or two versions, each missing one with a reason (no dressier piece, no other owned piece);
- `insufficient(InsufficientWardrobe)`: no valid outfit, with the kinds of piece that are missing.

A `StyleResult` has the versions, ranked owned alternatives per piece (for Swap and Show 3 more), and quiet notes ("You wore this last week", "Something new stays owned in a suitcase", "weather unavailable"). A failure to finish is not an outcome: the stylist throws `StylistError` (not completed, offline, timed out, cancelled), so a model or network problem can never be shown as "your closet is too small".

## The rules

Pure functions in `Models/Rules`, each with unit tests. Stores and screens both call them; no rule lives inside a store.

| Rule | What it decides | Spec |
|---|---|---|
| `Eligibility` | Which pieces may be styled: owned or arrived, not deleted, archived or unavailable, not dirty while tracking, and inside the suitcase | PRD §8.1, RD-11.2, LR-12.1 |
| `StylingContext.make` | Builds what the stylist gets: the request, eligible pieces from the source, and main-piece combinations worn inside the repeat window. Rejects a missing or archived suitcase and an unusable starting piece | PRD §8.1, LR-10 |
| `WearRules` | Calendar-day wear windows (1 week = today and the 6 days before), one wear per day, Undo, and recent main-piece combinations (tops, bottoms, dresses; shoes and single favourites can repeat) | LR-10 |
| `ResultCheck` | Checks a result before it's shown: Simple present, 2 to 6 pieces, only eligible pieces, ideas only in Something new and only when allowed, at most one, the starting piece in every version, every version shares a piece with Simple, "Same as Simple" marks right | PRD §8, LR-05a, LR-05b |
| `SuitcaseShelf` | Three favourites by most recent use, See all only above three, archived only under their filter | RD-09, LR-17 |
| `HamperState` | Off, all clean, or "2 to wash" | RD-11 |
| `GarmentFilter` | Piece chips, colour swatches, the Suitcase filter, the Dirty chip and typed search, all combined. Every typed word must match the name, brand, colour note, a suitcase name, or an extra word the screen passes in (Closet passes its names for the piece's kind and colours) | LR-09, LR-11, RD-11 |
| `GarmentRules` | The Add a piece form: a name and a kind required, length limits on the shade, brand, size and notes, one-line fields. Every problem at once, by field. Stores run it on every garment save | Phase 7b |
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
```

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
| `stores-fail` | Every store call throws `unavailable` (error states) |
| `photo-fails` | Add a piece's photo stand-in says the photo couldn't be read |

`draft=add` or `draft=edit` puts an unsaved draft in the draft store at launch, as if the app had been closed in the middle of Add a piece (the sage cardigan) or Edit (the navy dress pants renamed). Stage A drafts live in memory, so UI tests use it after a relaunch.

Add a piece's stand-ins: `InMemoryDraftStore`, `StandInPhotoIntake` (a sample picture for every source, no permission asked) and `WordMatchDescriptionReader` (Describe in words, a deterministic word matcher on the phone with no style rules).

Dates in the demo and large sets are relative to launch time, so "Last worn" reads naturally; tests pass a fixed date.

The **mock stylist** is deterministic and uses plain matching on stored facts only: occasion tags, season, warmth against the temperature, fit against comfort, and the colour wish. It pairs the best-matching main pieces with shoes, adds a layer in rain or cool weather, skips main-piece combinations worn inside the repeat window, swaps in a dressier owned piece for Dressed up, and adds one idea (or swaps another owned piece) for Something new. It has no real fit or styling rules; those stay in the private backend.

Performance, measured on an Apple-silicon Mac running the iOS 26.5 simulator in Debug: generating the large set 36 ms, five filters over it 35 ms, building a styling context 6 ms, styling 41 ms. The tests allow 1 s, 500 ms, 500 ms and 500 ms, so a failure means something got many times slower.

## Left out on purpose

- **Persistence, revisions and sync.** The PRD's revision numbers, deletion markers and sync conflicts arrive with real storage (Phases 20a to 21b). Adding them to in-memory fixtures now would be guesswork.
- **Favourites and collections** (PRD §8.2) have no Stage A screen (RD-08), so no type yet.
- **Find One, shopping and the fit check** (Phase 34). Wishlist pieces exist as an ownership state only.
- **Required versus preferred colour.** The request has one preferred colour for now. PRD §8.3's required colours and their scope come with the Style Me request phase (10a) if Lily needs them.
- **Swap ranking.** The result carries ranked alternatives; the on-phone swap list (LR-07) is built in Phase 11 from the same stored facts.

## Decisions for Jose

1. **No body measurements in the demo profile.** The repo is public and DATA_MAP.md asks fixtures to stay synthetic, so Lily's real height isn't in it. Tests use made-up values.
2. **Comfort and fit share three words.** Today's Comfort (fitted, comfortable, relaxed) maps one to one onto a garment's cut (fitted, regular, relaxed). It's a word match, not a fit rule.
3. **A mock outfit needs shoes plus a dress, or a top and a bottom.** So the demo Gym suitcase (a tee and sneakers) comes back insufficient, missing a bottom. The real stylist will decide this for itself.
4. **Suitcase icon** is a fixed set of five drawings (rolling, duffel, weekender, backpack, tote). The art comes in Phase 13.
