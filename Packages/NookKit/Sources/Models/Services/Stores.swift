import Foundation

// The store protocols. Features talk to these and never to a concrete store.
//
// Stage A has in-memory stores (Fixtures). Stage B puts real persistence behind the same
// protocols (Phase 20a). Each store is `Sendable` and every call is `async`, so an actor, a
// database or a sync engine can sit behind it. Stores keep data, not rules: the rules are the
// pure functions in Models/Rules, which screens and stores both call.

/// Why a store call failed.
public enum StoreError: Error, Hashable, Sendable {
    /// No record with that ID.
    case notFound
    /// The store couldn't read or write. Screens show their error state with Try again.
    case unavailable
    case cancelled
    case invalidName(NameProblem)
    case invalidMeasurements([MeasurementProblem])
}

/// Her garments: everything in Closet, plus wishlist, no-longer-owned, archived and Recently
/// deleted pieces. Screens filter with the rules (`Garment.isInCloset`, `Eligibility`,
/// `GarmentFilter`).
public protocol ClosetStore: Sendable {
    /// Every garment, newest first.
    func garments() async throws(StoreError) -> [Garment]
    func garment(_ id: Garment.ID) async throws(StoreError) -> Garment
    /// Adds a garment, or replaces the one with the same ID. Checks the name (`NameRules`).
    func save(_ garment: Garment) async throws(StoreError)
    /// Changes one garment in place and returns the new value. Checks the name.
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
}

/// Saved looks, looks she made herself, and unsaved results kept as background history (LR-06).
public protocol LookStore: Sendable {
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

/// Her suitcases and what's in them (PRD §7.7, RD-09, LR-11, LR-17).
public protocol SuitcaseStore: Sendable {
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
}

/// Her one profile.
public protocol ProfileStore: Sendable {
    func profile() async throws(StoreError) -> Profile
    /// Saves the profile after checking the sign name and measurements.
    func save(_ profile: Profile) async throws(StoreError)
}
