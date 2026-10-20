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

**Look** (Personal). Pieces, an optional name (set when saved), occasion, the source it was made from, `isSaved`, when it was saved (`savedAt`, Phase 12a, for "Saved 3 Oct" and Saved Looks' order), and wear days. Its try-on pictures point at it, not the other way round (Phase 12b). A styling result is one base outfit in three versions (LR-05a), so each version is its own Look with a `version` (Simple, Dressed up, Something new) and a shared `resultID`. A look she built in Make your own look has neither. Unsaved results stay in the store as background history (LR-06).

A **LookPiece** is either a garment she owns (by ID) or a **PieceIdea**: a described piece she doesn't own, shown as "Not in your closet" with Find one. An idea never becomes owned by being in a look. Each piece records whether it's the same as in Simple ("Same as Simple", LR-05a.3).

**TryOnPicture** (Sensitive, Phase 12b). A try-on picture of one look: the look's ID, the look as it was when the picture was made (`CapturedLook`: pieces, name, occasion), the image (`.simulated` in Stage A, drawn on the phone with no person; `.generated` from Phase 33) and when it was made. It stays until she deletes it, whatever happens to its look. See `docs/try-on-pictures.md`.

**LookDraft** (Personal, Phase 11). A look she started in Make your own look and hasn't saved: her name for it so far, the source, the pieces, the starting piece, when it was written. One at a time, in `LookDraftStore`. See `docs/swap-and-editor.md`.

**Suitcase** (Personal). Name, icon (which drawing stands for it in the hall), the set of garment IDs it holds (it never copies a garment), `lastUsedAt`, archived, created. Favourites come from `lastUsedAt`. A piece she no longer has keeps its link, but screens only show and count pieces in her closet (`SourceChoice.pieces`, Phase 13).

**Profile**. The sign name (Personal, may be empty), Preferences (Personal), usual fit, liked and avoided colours, the units Fit shows (`units`, Phase 14a; `nil` means the region's usual ones), and three Sensitive groups: body measurements (all optional, each with its unit), "pieces that fit you well" (LR-13), and the try-on photo. The doc comment on each field names its tier. `BodyMeasurements` prints as "redacted" and has no mirror children, so a log line or `dump` can't leak it.

**RememberedChoices** (Personal, Phase 13), `Profile.remembered`: the source and occasion she chose last, which Style Me starts from and Home's suitcase and calendar show (FR-67). See `docs/suitcases-and-laundry.md`.

**FeedbackNote** (Personal, Phase 14b): what it's about, her words (trimmed, at most 1,000 characters, `FeedbackRules`), and the app details (`FeedbackDiagnostics`: version, build, iOS version, model identifier) only when she adds them. Nothing about her closet, body or name is part of it. See `docs/settings.md`.

**OnboardingState** (Phase 17, `docs/onboarding.md`): whether onboarding is finished and the starting closet she chose (`StartingCloset`: sample or empty). App state in the lowest tier, kept across launches. Her answers (`OnboardingAnswers`: the sign name and usual fit) go to the profile.

**TourProgress** (Phase 16a): the tours seen. Since Phase 17 `seenVersions` and the tips switch are kept across launches, and `records` (how and when each ended) only for the session (`docs/tours.md`).

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
| `LaundryBasket` | What's in the wash (pieces in her closet only), in the whole closet or one suitcase, and which pieces Mark clean and its Undo may change | PRD §7.3, FR-65 |
| `SourceChoice` | The source to show: the remembered one, or the main closet once its suitcase is deleted or archived; and the pieces of her closet in a source | FR-67, PRD §7.7, LR-16.1 |
| `GarmentFilter` | Piece chips, colour swatches, the Suitcase filter, the Dirty chip and typed search, all combined. Every typed word must match the name, brand, colour note, a suitcase name, or an extra word the screen passes in (Closet passes its names for the piece's kind and colours) | LR-09, LR-11, RD-11 |
| `StyleRequestBuilder` | Checks a Style Me draft before it's sent: an empty closet or suitcase, a missing suitcase, too few usable pieces (stops it), a small suitcase (warns), a starting piece that can't be used, Other's words, a required colour nothing usable has (warns). Builds the request | RD-02, FR-67, PRD §8.1, §8.3 |
| `LookFilter` | Saved Looks' piece chips, colour swatches and typed search. A chip and a swatch match one piece together ("black bottoms"); every typed word must match the look's name, a piece's name, or the screen's words for the occasion, kinds and colours | RD-08, LR-09 |
| `GarmentRules` | The Add a piece form: a name and a kind required, length limits on the shade, brand, size and notes, one-line fields. Every problem at once, by field. Stores run it on every garment save | Phase 7b |
| `CutoutThresholds` | Whether a cutout's signals are clean enough for a sticker. `current` is 8a's proposal until the benchmark on her phone | RD-07, Phase 8a |
| `GarmentArtChoice` | How a piece's picture shows: its drawing (no photo), its cutout (clean), or its photo in a tile (no cutout yet, or a concern) | RD-07, Phase 8b |
| `SwapRanking` | Swap a piece's options: her pieces of the same kind she can wear from the look's source, good matches (occasion, weather, colours that sit with the rest) best first, weaker ones and outfits worn lately set aside for See all | LR-07, LR-10, Phase 11 |
| `TryOnLinks` | Where a picture's look is now (current, changed since, not in Saved Looks), a look's pictures newest first, and the picture of exactly this look to offer before making another | RD-08.2, PRD §7.5, FR-59 |
| `LookEditing` | One piece replaced or removed, as a new look that keeps its version, occasion, source and other pieces | FR-09, LR-08 |
| `LookRules` | A hand-made or hand-changed look: 2 to 6 pieces, a dress or a top and a bottom, one of each kind in Make your own look, every piece wearable | RD-07.1, LR-08 |
| `EditHistory` | Undo and Redo of whole values, up to 20 | PRD §7.3, LR-08.2 |
| `NameRules`, `MeasurementRules` | Trimmed names with length limits, no control characters, unique suitcase names; measurement sanity ranges (they catch typos and say nothing about fit); a fitting piece's brand and size | RD-03.2, LR-13 |
| `MeasurementEntry` | Typed text to a stored length or weight: either decimal mark, empty means no value (never zero), feet and inches for height, the range shown in her units (Phase 14a, `docs/profile.md`) | PRD §10.1, §10.2 |

## The store protocol

Features talk only to these. Each is `Sendable` with `async` calls and typed errors (`StoreError`: not found, unavailable, cancelled, invalid name, invalid details, invalid measurements), so an actor, a database or a sync engine can sit behind it. Stage A has in-memory actors; since Phase 21a the real stores keep her data in a SwiftData store on the iPhone, behind the same protocols (see Real storage below).

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
    func deletePermanently(_ id: Garment.ID) async throws(StoreError)  // Phase 21a: only from Recently deleted
}

protocol LookStore: Sendable { looks, look, save, update, delete, recordWear, removeWear }
protocol SuitcaseStore: Sendable { suitcases, suitcase, create(name:icon:at:), update, add, remove, markUsed, delete, restore }
protocol ProfileStore: Sendable { profile, save, update }   // both check the sign name, measurements and fit pieces
// ProfileStore.update { } changes one setting in place, as one step, so two changes at once both land

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

// Phase 12b, Try it on and the Pictures tab
protocol TryOnPictureStore: Sendable { pictures, picture, save, delete }   // every picture, newest first
protocol TryOnService: Sendable { func makePicture(of: Look, at: Date) async throws(TryOnError) -> TryOnPicture }

// Phase 16a and 17, kept across launches (in the real store since Phase 21a)
protocol TourProgressStore: ErasableStore { progress, record, setShowsTipsOnNewScreens, forgetSeenTours }
protocol OnboardingStateStore: ErasableStore { state, complete(startingCloset:) }

// Phase 21a, the unsent Send feedback note
protocol FeedbackDraftStore: ErasableStore { draft, save, discard }

// Phase 14b, Delete my data
protocol ErasableStore: Sendable { func eraseAll() async throws(StoreError) }   // every store above refines it
protocol DataDeletionService: Sendable { scopes, parts(in:), delete(_:) -> DeletionReport }
```

Every store protocol refines `ErasableStore`, so Delete my data can empty each one through its protocol (a fresh profile for `ProfileStore`, and since Phase 17 the onboarding state last). `NookServices.deletion` is `LocalDataDeletion` over the stores it holds when it's read (so a store swapped in later is the one erased) unless it's given another; it reports each `DataPart` as deleted, pending (a server part, from 24c) or failed. See `docs/settings.md`.

Stage A's `TryOnService` is `SimulatedTryOn`: it returns a `.simulated` picture after a moment and sends nothing. The screen keeps the picture in the store before it says it's ready.

`CutoutResult` is the subject as a PNG on transparency with `CutoutQuality` signals; `CutoutThresholds` (a rule) turns them into sticker or tile. Stage A's `NookServices.cutouts` is `StandInCutoutService`, which hands the photo back with the signals it was given. The Vision implementation lives in the `Services` module and is described in `docs/cutout-feasibility.md`.

`NookServices` bundles one of each. Since Phase 17 the app target hands `AppRootView` an `AppLaunch`: the two stores kept across launches and a way to build the services for the closet she chose in onboarding (`FixtureServices.make(_:startingCloset:tours:onboarding:)`). Since Phase 21a `FixtureServices.make` also takes `stores:`, a `NookStoreSet` of real stores that replaces the in-memory ones (the sample set's data, the store options and `draft=` then don't apply), and `NookServices.keepsChanges` says whether her changes outlive the app (true for the real stores, false for the debug sample closet), which Help and Privacy and terms use for their words. The root puts the services in the SwiftUI environment (`\.services`). Screens never build services. Without them (a preview, or a test that doesn't need data) a screen gets `NookServices.unavailable`, whose every call fails, so it shows its error state rather than pretending to load or save.

Screens load from `.task` and again after a pushed screen closes, Undo or Try again, so loads can overlap. Each model numbers its loads (`LoadGeneration` in Features/Shared) and only the newest shows what it read, so an older load that finishes last can't put back data from before a change.

A store returns everything it holds and leaves filtering to the rules: Closet shows `isInCloset`, Saved Looks shows `isSaved`, Suitcases arranges with `SuitcaseShelf`. Wear today on a look writes to two stores, the look and then its pieces, so neither store needs to know about the other. `LookWear` (Models) does both: if the pieces can't be written it puts the look back as it was and throws, so the look and its pieces never disagree.

### Store contracts and validation

What a store checks before it keeps a record is in `StoreValidation` (Models/Rules): garments, looks, suitcase names and the profile, each built from `NameRules`, `GarmentRules` and `MeasurementRules`. Every store calls it, so Stage A's in-memory stores and Stage B's real ones refuse the same records.

What every store does is written once as a contract in the `NookTestSupport` target (`Tests/NookTestSupport/StoreContracts`): one per store protocol, each a list of checks run against a factory that makes the store. FixturesTests runs them on every in-memory store, and ServicesTests on every real store, each on a store file of its own (`StoredStoreContractTests`, Phase 21a), and on the old `UserDefaults` app-state stores the import reads. `NookTestSupport` also holds `TestTime` and `SpeedCheck`, which every test target shares; only test targets depend on it.

## Real storage (Phase 21a)

Her data lives in one SwiftData store on the iPhone, in `Application Support/Store/Nook.store`, as Phase 20a recommended (`docs/decisions/0003-persistence-spike.md`). The code is in `Services/Storage`.

| Part | File | What it does |
|---|---|---|
| Schema | `StoreSchema.swift` | One entity, `StoredRecord`: a kind (`garment`, `look`, `suitcase`, `picture`, `garmentDraft`, `lookDraft`, `feedbackDraft`, `profile`, `onboarding`, `tours`, `defaultsImport`, and since 21b `deletion` and `restoreConflict`), the record's stable ID within it, the value type as JSON (`payload`) and the JSON's version (`payloadVersion`). Kind and key are unique together. `NookSchemaV1` is the first version and `NookMigrationPlan` lists every version and stage |
| Payloads | `RecordPayload.swift` | Encodes and decodes the value types' own `Codable` JSON. Reads every payload version up to its own and refuses a newer one. `RecordPayloadTests` holds a version 1 payload of every kind, which every later build must still read |
| Stores | `StoredClosetStores.swift`, `StoredSmallStores.swift` | A `@ModelActor` per protocol, each with its own context, handing out value types only. The closet, look, suitcase and picture stores keep what they read in memory and write through, so lists come back as fast as from memory. Every write is saved before the call returns |
| Opening and migrations | `MigrationCoordinator.swift`, `StoreLocation.swift` | The spike's coordinator, promoted: the store's version read from its metadata before anything opens it, a free-space check, a journal before every step, a snapshot (left out of device backups) and a manifest of every record's kind, key and payload hash, SwiftData's migration, a check against the manifest, the snapshot put back at the next launch if anything stopped or didn't match, three tries per app build, and the snapshot deleted seven days after a verified migration. A store from a newer app, or a file that isn't a store, is never opened or reset |
| The whole store | `NookStorage.swift` | Opens the store and makes every store on it; the store set for `FixtureServices`, the kept-settings keeper for the debug sample closet, and the list Delete my data erases. Since 21b it finishes or tidies up a stopped restore at launch, holds the backup service, and `reload()` makes fresh store actors after a restore |
| Backups (21b) | `Backup/` | Export, Check a copy, Restore and Undo restore (`docs/decisions/0004-backup-and-recovery.md`, "Built in Phase 21b"): the encrypted archive (`BackupArchive`), its format and limits, records as readable JSON through the value types (`BackupRecords`), the export, the checks, the restore plan, and the committer with its journal and safety copy |
| Moving Stage A's suite in | `AppState/AppStateDefaultsImport.swift` | At the first launch of a 21a build, the onboarding state, tours seen, tips switch, name on the sign and three Style Me settings move from the `UserDefaults` suite into the store, then the suite is emptied. Values already in the store win; killed half way, it runs again with the same result |

**One table with a payload per record.** The 20b design exports JSON records and puts one encrypted payload in each CloudKit record, so the store keeps the same JSON. The value types change often; a change to one is a change to its `Codable` shape (a new payload version when old JSON no longer decodes), not to the SwiftData schema, which stays small. Schema changes still happen (new columns or entities for sync), and each one goes through `NookMigrationPlan` and the coordinator. Records refer to each other by stable ID inside the payload, never by SwiftData relationship, so a look keeps a piece that was deleted for good as a gap (20a's finding).

**Where each build keeps what.**

| | Her closet, looks, suitcases, pictures, profile, drafts, feedback note | Onboarding and tours seen |
|---|---|---|
| Release | The store | The store |
| Debug, empty closet | The store | The store |
| Debug, sample closet | In memory, from the fixtures, as it ships at each launch; only the name on the sign and the Style Me settings are kept, in the store's profile record (`StoredProfileSettingsKeeper`); the feedback note is kept | The store |
| Debug, `-onboarding skip` | In memory, from the fixtures; nothing kept | The store |

So `-fixtures` and its options keep working for the sample closet, and the UI tests (all on `-onboarding skip`) start from the same data every time. Delete my data on the sample closet also erases the store, and `-onboarding reset` erases everything in it but the tours, so nothing from an earlier closet comes back.

**Protection.** The app's entitlement makes Data Protection `complete` the default for every file; the store's folder and files and the journal are also given it in code. The simulator doesn't keep protection classes, so the classes on a device are still to check (with the store's `-wal` and `-shm`, and that it can't be read while the phone is locked). No store error is logged: SwiftData errors can quote the values being saved.

**If the store can't be opened** (a newer app's store, a failed migration after three tries, not enough space for the safety copy, or a file it can't read), the app shows a short screen saying what happened and that nothing was deleted (`StoreProblemView`, words from 0004 §7), instead of onboarding or the tabs. Since 21b it has Export a copy, which saves the raw store and photos, encrypted, for a later version to restore; Try again and Send feedback wait (see `docs/settings.md`).

**Tests.** `StoredStoreContractTests` (every contract on every real store), `StoragePersistenceTests` (every demo record and 300 large-closet garments round-trip through a relaunch field for field; changes on disk when the call returns; drafts, the note, onboarding and tours kept; a piece deleted for good stays gone; Delete my data leaves no record; no CloudKit), `MigrationCoordinatorTests` (a test-only version 2, lightweight and custom; a crash at each of 11 checkpoints recovering with every record intact; a newer or damaged store left alone; not enough space; a migration that loses a record rolled back, stopping after three tries and retrying in a new build; the seven-day cleanup), `AppStateDefaultsImportTests` and `RecordPayloadTests`. The test version 2 adds an entity rather than changing `StoredRecord`, because 20a found that changing a class other tests in the same process still use makes SwiftData crash; the manual run in the build plan's 21a entry changed `StoredRecord` itself.

## Fixtures

Pick a set with `-fixtures <set>`, and optionally options after colons: a behaviour (`-fixtures demo:offline`), `weather=<state>` and `laundry=<state>` (`-fixtures demo:weather=night:laundry=full`), and `source=suitcase` for a remembered suitcase source (Phase 13). The README lists every value. Unknown values fall back to `demo`, `normal` and the set's own weather and laundry.

| Set | Contents |
|---|---|
| `empty` | A fresh install: nothing, default preferences, empty sign name |
| `demo` | The prototype's 21 garments in the new model (every state: wishlist, bought not arrived, no longer owned, Recently deleted, archived, at the tailor, dirty, text-only (the old gray leggings; the other 20 pieces have a sample photo and cutout), worn recently and long ago), ten looks (including a saved Something new with an idea piece, one she made herself, an unsaved result, and four matching the sample try-on previews), seven try-on pictures (three simulated, two of Interview and one of an earlier version, and four previews of her wearing a look), six suitcases (one empty, one archived, five active so See all shows), and a profile named Lily. Weather: 58° and rain |
| `large` | 2,400 generated garments, 600 looks, 40 suitcases and a simulated picture for every third saved look, from a fixed seed, so every run is the same |

| Behaviour | What happens |
|---|---|
| `normal` | Everything answers at once |
| `slow` | Stores wait 0.6 s, weather 1 s, the stylist 3 s (loading states) |
| `offline` | The stylist and Try it on throw `offline` and weather can't be read; local stores still work |
| `stylist-fails` | The stylist throws `notCompleted` |
| `stylist-partial` | The stylist returns Simple and Dressed up only |
| `stylist-insufficient` | The stylist says the source can't make a look (a bottom and shoes missing) |
| `stylist-waits` | The stylist never answers until cancelled, for Your looks' styling state |
| `offline-once` | The first styling request fails as offline and later ones work, as if the connection came back. Weather and stores work |
| `stores-fail` | Every store call throws `unavailable` (error states) |
| `photo-fails` | Add a piece's photo stand-in says the photo couldn't be read |
| `picture-fails` | Try it on doesn't finish (Phase 12b) |

`photos=` is `real` (the default: pieces with a photo show the bundled sample wardrobe through `SampleWardrobeProvider`, the drawings are the fallback), `drawn` (the drawings only, as before) or `samples`. `wardrobe=full` adds 30 more pieces with photos (one or more of every category), the sundress and cool-weather looks and their previews, to the demo set only. Pieces carry the photo and cutout as `PhotoReference.sample` names; the shape of `Garment`, `GarmentCutout` and `TryOnPicture` didn't change, and a `.generated` picture now has a fixture meaning (`docs/try-on-pictures.md`). The large set takes the same photos by kind and colour. The images, their README and the script that makes them are in `Fixtures/Resources/SampleWardrobe` and `scripts/build-sample-wardrobe.swift`.

`photos=samples` adds eight pieces with drawn sample photos and stand-in cutouts, and an image provider (`SamplePhotoProvider`) that draws them, so stickers and tiles can be seen without real photos (Phase 8b, `docs/stickers.md`).

`draft=add` or `draft=edit` puts an unsaved draft in the draft store at launch, as if the app had been closed in the middle of Add a piece (the sage cardigan) or Edit (the navy dress pants renamed). `draft=look` puts a half-built Make your own look in the look draft store ("Pink for Friday": the pink shirt and the navy dress pants, Phase 11). The sample closet's drafts live in memory, so UI tests use it after a relaunch. It doesn't apply to her own closet in the real store, where drafts are kept anyway.

Add a piece's stand-ins: `InMemoryDraftStore`, `StandInPhotoIntake` (a sample picture for every source, no permission asked) and `WordMatchDescriptionReader` (Describe in words, a deterministic word matcher on the phone with no style rules).

Dates in the demo and large sets are relative to launch time, so "Last worn" reads naturally; tests pass a fixed date.

The **mock stylist** is deterministic and uses plain matching on stored facts only: occasion tags, season, warmth against the temperature, fit against comfort, and the colour wish where she asked for it (a required colour counts the same as a preferred one when matching; since 10b a result says when a required colour couldn't be met). It pairs the best-matching main pieces with shoes, adds a layer in rain or cool weather, skips main-piece combinations worn inside the repeat window, swaps in a dressier owned piece for Dressed up, and adds one idea (or swaps another owned piece) for Something new. For Try a different outfit it starts from a base not shown yet, and says so when every base has been shown. It has no real fit or styling rules; those stay in the private backend.

Performance, measured on an Apple-silicon Mac running the iOS 26.5 simulator in Debug: generating the large set 36 ms, five filters over it 35 ms, building a styling context 6 ms, styling 41 ms. The tests allow 1 s, 500 ms, 500 ms and 500 ms, so a failure means something got many times slower. Each check takes the fastest of three runs and allows three times as long on CI, after two checks went over once on a busy CI runner (a context build took 862 ms there, against 6 ms locally).

## Left out on purpose

- **Revisions and sync.** Since Phase 21a her data is kept in the real store (below). Since 21b a piece deleted for good leaves a content-free deletion marker (`RecordKind.deletion`) in the same save, which exports carry and restores obey. The PRD's revision numbers and sync conflicts arrive with sync. Adding them to in-memory fixtures now would be guesswork. Phase 20b's design (`docs/decisions/0004-backup-and-recovery.md`) keeps sync bookkeeping (change tags, the ancestor payload for three-way merges, the `CKSyncEngine` state) in the store beside the records, never in these value types, and exports and syncs the value types themselves as versioned JSON.
- **Favourites and collections** (PRD §8.2) have no Stage A screen (RD-08), so no type yet.
- **Find One, shopping and the fit check** (Phase 34). Wishlist pieces exist as an ownership state only.
- **More than one colour.** Since 10a the request has one colour wish, preferred or required, with its place (PRD §8.3). Several colours at once, or explicit monochrome, can come later if Lily asks.
- **Swap ranking on the server.** Phase 11 ranks swaps on the phone with `SwapRanking` (plain matching on stored facts). The stylist's own `alternates` aren't used by Swap yet; better ranking that needs the private rules would be a server call later.

## Decisions for Jose

1. **No body measurements in the demo profile.** The repo is public and DATA_MAP.md asks fixtures to stay synthetic, so Lily's real height isn't in it. Tests use made-up values.
2. **Comfort and fit share three words.** Today's Comfort (fitted, comfortable, relaxed) maps one to one onto a garment's cut (fitted, regular, relaxed). It's a word match, not a fit rule.
3. **A mock outfit needs shoes plus a dress, or a top and a bottom.** So the demo Gym suitcase (a tee and sneakers) comes back insufficient, missing a bottom. The real stylist will decide this for itself.
4. **Suitcase icon** is a fixed set of five drawings (rolling, duffel, weekender, backpack, tote). Phase 13 drew them; see `docs/suitcases-and-laundry.md`.
