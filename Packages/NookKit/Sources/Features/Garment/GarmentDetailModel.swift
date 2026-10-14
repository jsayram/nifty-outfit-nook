import Foundation
import Models
import Observation

/// One piece's detail: the garment, the suitcases it's in (LR-11), the saved looks that use it
/// (for Delete it, LR-16.2), and her laundry and repeat settings (RD-11, LR-10).
///
/// The words come from `GarmentDetailText`. This model loads, and makes the changes the screen
/// offers: mark dirty or clean, "I don't have it any more" and "Delete it". Each change goes
/// through the `ClosetStore`, so Stage B's real store gets the same calls.
@Observable
final class GarmentDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The piece isn't there any more: deleted elsewhere, or purged.
        case gone
        /// A store failed. The screen shows its error state with Try again.
        case failed
    }

    let garmentID: Garment.ID
    private(set) var phase: Phase = .loading
    private(set) var garment: Garment?
    /// Her active suitcases that hold it, by name (LR-11). Archived suitcases don't count.
    private(set) var suitcases: [Suitcase] = []
    /// Her saved looks that use it, newest first. Delete it lists them first (LR-16.2).
    private(set) var savedLooks: [Look] = []
    private(set) var tracksLaundry = false
    private(set) var repeatWindow: RepeatWindow = .oneWeek
    /// When it loaded, for "Last worn 3 days ago".
    private(set) var loadedAt: Date = .now
    /// True while a change is being saved, so a second tap does nothing.
    private(set) var isSaving = false

    init(garmentID: Garment.ID) {
        self.garmentID = garmentID
    }

    // MARK: Loading

    func load(from services: NookServices?, now: Date = .now) async {
        guard let services else {
            phase = .gone
            return
        }
        if garment == nil { phase = .loading }
        do {
            async let piece = services.closet.garment(garmentID)
            async let suitcaseList = services.suitcases.suitcases()
            async let lookList = services.looks.looks()
            async let profile = services.profile.profile()
            show(
                try await piece, suitcases: try await suitcaseList, looks: try await lookList,
                profile: try await profile, now: now)
        } catch StoreError.notFound {
            garment = nil
            phase = .gone
        } catch {
            phase = .failed
        }
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(_ garment: Garment, suitcases allSuitcases: [Suitcase], looks: [Look], profile: Profile, now: Date) {
        loadedAt = now
        tracksLaundry = profile.preferences.tracksLaundry
        repeatWindow = profile.preferences.repeatWindow
        // A piece in Recently deleted has no detail; Recently deleted lists it instead.
        guard !garment.isDeleted else {
            self.garment = nil
            phase = .gone
            return
        }
        self.garment = garment
        suitcases = allSuitcases.filter { !$0.isArchived && $0.contains(garment.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        savedLooks = looks.filter { $0.isSaved && $0.garmentIDs.contains(garment.id) }
        phase = .loaded
    }

    /// The words for the loaded piece.
    func text(calendar: Calendar, locale: Locale) -> GarmentDetailText? {
        garment.map {
            GarmentDetailText(
                garment: $0, tracksLaundry: tracksLaundry, repeatWindow: repeatWindow, now: loadedAt,
                calendar: calendar, locale: locale)
        }
    }

    /// True when the piece is in her closet, so the actions apply. A piece she no longer has can
    /// still be shown (from an old saved look, later), with no actions.
    var isInCloset: Bool { garment?.isInCloset ?? false }

    /// True when Mark as dirty or Mark as clean shows: tracking is on (RD-11.1).
    var showsLaundryAction: Bool { tracksLaundry && isInCloset }

    /// The saved looks' names, for the Delete it step (LR-16.2). A look with no name gets a
    /// plain stand-in.
    var savedLookNames: [String] {
        savedLooks.map { look in
            look.name ?? String(localized: "A look with no name", bundle: .module, comment: "Saved look with no name")
        }
    }

    // MARK: Changes

    /// Marks it dirty or clean (RD-11). Returns the state it had, for Undo.
    @discardableResult
    func setLaundry(_ state: LaundryState, in closet: any ClosetStore) async throws(StoreError) -> LaundryState? {
        guard let previous = garment?.laundry, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        try await closet.setLaundry(state, for: [garmentID])
        garment?.laundry = state
        return previous
    }

    /// "I don't have it any more" (LR-16.1, PRD §7.4 No longer own): out of Closet, suitcases and
    /// styling, kept in her history with its links. Undo puts back the ownership it had.
    func markNoLongerOwned(in closet: any ClosetStore) async throws(StoreError) -> GarmentRemoval? {
        guard let garment, garment.isInCloset, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        let previous = garment.ownership
        self.garment = try await closet.update(garmentID) { $0.ownership = .noLongerOwned }
        return GarmentRemoval(garmentID: garmentID, name: garment.name, kind: .noLongerOwned(previous: previous))
    }

    /// "Delete it" (LR-16.2): to Recently deleted for 30 days. Restore brings back the same piece
    /// and its links (LR-16.3).
    func delete(in closet: any ClosetStore, at date: Date) async throws(StoreError) -> GarmentRemoval? {
        guard let garment, garment.isInCloset, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        try await closet.delete(garmentID, at: date)
        self.garment?.deletedAt = date
        return GarmentRemoval(garmentID: garmentID, name: garment.name, kind: .deleted)
    }
}

/// A piece she just took out of her closet, with how to undo it (LR-16.1).
nonisolated struct GarmentRemoval: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// "I don't have it any more". Undo puts this ownership back.
        case noLongerOwned(previous: Ownership)
        /// "Delete it". Undo restores it from Recently deleted.
        case deleted
    }

    let garmentID: Garment.ID
    let name: String
    let kind: Kind

    /// What the toast says.
    var message: String {
        switch kind {
        case .noLongerOwned:
            String(
                localized: "\(name) is out of your closet", bundle: .module,
                comment: "Toast after I don't have it any more, with the piece's name")
        case .deleted:
            String(
                localized: "\(name) is in Recently deleted", bundle: .module,
                comment: "Toast after Delete it, with the piece's name")
        }
    }

    /// Undo: back in her closet, the same piece with the same links.
    func undo(in closet: any ClosetStore) async throws(StoreError) {
        switch kind {
        case .noLongerOwned(let previous):
            try await closet.update(garmentID) { $0.ownership = previous }
        case .deleted:
            try await closet.restore(garmentID)
        }
    }
}
