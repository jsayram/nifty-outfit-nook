import Foundation

// The store protocols. Features talk to these and never to a concrete store.
//
// Stage A has in-memory stores (Fixtures). Since Phase 21a the real stores (Services/Storage) keep
// everything in a SwiftData store on the iPhone, behind the same protocols. Each store is `Sendable` and every call is `async`, so an actor, a database or a
// sync engine can sit behind it. Stores keep data, not rules: the rules are the pure functions in
// Models/Rules, which screens and stores both call, and every store checks a record on save with
// `StoreValidation`. The store contracts in NookTestSupport say what each store must do.

/// Why a store call failed.
public enum StoreError: Error, Hashable, Sendable {
    /// No record with that ID.
    case notFound
    /// The store couldn't read or write. Screens show their error state with Try again.
    case unavailable
    case cancelled
    case invalidName(NameProblem)
    /// A garment's other text fields were refused (`GarmentRules`): too long, or a line break in
    /// a one-line field.
    case invalidDetails(GarmentProblems)
    case invalidMeasurements([MeasurementProblem])
}

/// Her garments: everything in Closet, plus wishlist, no-longer-owned, archived and Recently
/// deleted pieces. Screens filter with the rules (`Garment.isInCloset`, `Eligibility`,
/// `GarmentFilter`).
public protocol ClosetStore: ErasableStore {
    /// Every garment, newest first.
    func garments() async throws(StoreError) -> [Garment]
    func garment(_ id: Garment.ID) async throws(StoreError) -> Garment
    /// Adds a garment, or replaces the one with the same ID. Checks the name (`NameRules`) and
    /// the other text fields (`GarmentRules`).
    func save(_ garment: Garment) async throws(StoreError)
    /// Changes one garment in place and returns the new value. Checks it as `save` does.
    @discardableResult
    func update(
        _ id: Garment.ID,
        _ change: @Sendable (inout Garment) -> Void
    ) async throws(StoreError) -> Garment
    /// Wear today for these pieces (LR-10). One entry per day; laundry is untouched.
    func recordWear(of ids: [Garment.ID], on date: Date) async throws(StoreError)
    /// Undo for Wear today.
    func removeWear(of ids: [Garment.ID], on date: Date) async throws(StoreError)
    /// Mark dirty or clean. Allowed while tracking is off; the marks just don't show (RD-11).
    func setLaundry(_ state: LaundryState, for ids: [Garment.ID]) async throws(StoreError)
    /// "Delete it": moves the piece to Recently deleted for 30 days (LR-16).
    func delete(_ id: Garment.ID, at date: Date) async throws(StoreError)
    /// Brings a piece back from Recently deleted with its links intact (LR-16.3).
    func restore(_ id: Garment.ID) async throws(StoreError)
    /// Removes pieces whose 30 days are up, and returns their IDs.
    func purgeExpired(asOf date: Date) async throws(StoreError) -> [Garment.ID]
    /// "Delete permanently now" in Recently deleted (PRD §7.4, Phase 21a): removes a piece that's
    /// in Recently deleted for good, before its 30 days are up. A piece that isn't in Recently
    /// deleted, or isn't there at all, is `notFound`, so this can never remove a piece in her
    /// closet. `PermanentDeletion` says what else goes with it.
    func deletePermanently(_ id: Garment.ID) async throws(StoreError)
}

/// Saved looks, looks she made herself, and unsaved results kept as background history (LR-06).
public protocol LookStore: ErasableStore {
    /// Every look, newest first. Saved Looks shows the ones with `isSaved`.
    func looks() async throws(StoreError) -> [Look]
    func look(_ id: Look.ID) async throws(StoreError) -> Look
    /// Adds a look, or replaces the one with the same ID. Checks the name of a named look.
    func save(_ look: Look) async throws(StoreError)
    @discardableResult
    func update(_ id: Look.ID, _ change: @Sendable (inout Look) -> Void) async throws(StoreError) -> Look
    func delete(_ id: Look.ID) async throws(StoreError)
    /// Wear today for a look (LR-10). The screen also records it on the pieces (`ClosetStore`).
    func recordWear(of id: Look.ID, on date: Date) async throws(StoreError)
    func removeWear(of id: Look.ID, on date: Date) async throws(StoreError)
}

/// Her try-on pictures (RD-08, Phase 12b). Sensitive: a real one is a picture of her.
///
/// Every picture stays until she deletes it, whatever happens to its look (PRD §7.5, §9.2.4).
/// The rules for how pictures and looks link are in `TryOnLinks`.
public protocol TryOnPictureStore: ErasableStore {
    /// Every picture, newest first.
    func pictures() async throws(StoreError) -> [TryOnPicture]
    func picture(_ id: TryOnPicture.ID) async throws(StoreError) -> TryOnPicture
    /// Keeps a new picture, or puts back the one with the same ID (Undo after Delete picture).
    func save(_ picture: TryOnPicture) async throws(StoreError)
    /// Delete picture. Stage B also removes its image file (Phase 22b).
    func delete(_ id: TryOnPicture.ID) async throws(StoreError)
}

/// Her suitcases and what's in them (PRD §7.7, RD-09, LR-11, LR-17).
public protocol SuitcaseStore: ErasableStore {
    /// Every suitcase, archived ones included. `SuitcaseShelf` arranges them.
    func suitcases() async throws(StoreError) -> [Suitcase]
    func suitcase(_ id: Suitcase.ID) async throws(StoreError) -> Suitcase
    /// "+ Add a suitcase". The name must be unique among her suitcases.
    func create(name: String, icon: SuitcaseIcon, at date: Date) async throws(StoreError) -> Suitcase
    /// Changes one suitcase in place. A new name must still be unique.
    @discardableResult
    func update(_ id: Suitcase.ID, _ change: @Sendable (inout Suitcase) -> Void) async throws(StoreError) -> Suitcase
    func add(_ garmentIDs: [Garment.ID], to id: Suitcase.ID) async throws(StoreError)
    func remove(_ garmentIDs: [Garment.ID], from id: Suitcase.ID) async throws(StoreError)
    /// Records the suitcase as the Style Me source, which makes it a favourite (RD-09.2).
    func markUsed(_ id: Suitcase.ID, at date: Date) async throws(StoreError)
    /// Deletes the suitcase only. Its garments and looks stay (PRD §12).
    func delete(_ id: Suitcase.ID) async throws(StoreError)
    /// Undo after a delete: puts back exactly this suitcase, with its ID, name and pieces
    /// (Phase 13). Fails with `invalidName` if another suitcase took the name meanwhile.
    func restore(_ suitcase: Suitcase) async throws(StoreError)
}

/// Every store that holds her data, as one value. The app hands a set to `FixtureServices` when
/// the data lives in the real store on the iPhone (Phase 21a), instead of the in-memory stores.
public struct NookStoreSet: Sendable {
    public var closet: any ClosetStore
    public var looks: any LookStore
    public var suitcases: any SuitcaseStore
    public var profile: any ProfileStore
    public var drafts: any DraftStore
    public var lookDrafts: any LookDraftStore
    public var pictures: any TryOnPictureStore
    public var feedbackDrafts: any FeedbackDraftStore

    public init(
        closet: any ClosetStore, looks: any LookStore, suitcases: any SuitcaseStore, profile: any ProfileStore,
        drafts: any DraftStore, lookDrafts: any LookDraftStore, pictures: any TryOnPictureStore,
        feedbackDrafts: any FeedbackDraftStore
    ) {
        self.closet = closet
        self.looks = looks
        self.suitcases = suitcases
        self.profile = profile
        self.drafts = drafts
        self.lookDrafts = lookDrafts
        self.pictures = pictures
        self.feedbackDrafts = feedbackDrafts
    }
}

/// Her one profile. Erasing it leaves a fresh profile: no name, the default Preferences, no
/// measurements, fitting pieces or try-on photo.
public protocol ProfileStore: ErasableStore {
    func profile() async throws(StoreError) -> Profile
    /// Saves the profile after checking the sign name and measurements (`ProfileValidation`).
    func save(_ profile: Profile) async throws(StoreError)
    /// Changes the profile in place and returns what was saved, for one setting at a time (Track
    /// laundry, the remembered source). Checks it as `save` does. The read, the change and the
    /// write are one step, so two changes made at once both land.
    @discardableResult
    func update(_ change: @Sendable (inout Profile) -> Void) async throws(StoreError) -> Profile
}
