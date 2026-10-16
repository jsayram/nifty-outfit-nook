import Foundation
import Models
import Observation

/// Laundry (`laundry.html`, RD-11, PRD §7.3, FR-64, FR-65): the pieces in the wash, and marking
/// them clean one at a time, a few she ticks, or all of them, each with Undo.
///
/// When Style Me's source is a suitcase, she can look at the whole closet or only that
/// suitcase ("This suitcase", PRD §7.3). While tracking is off the screen says so and offers Turn
/// on; her marks are kept (RD-11). Cleaning only changes pieces still in her closet and still in
/// the wash; anything else is skipped, never forced (`LaundryBasket`).
@Observable
final class LaundryModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// A store failed. The screen shows its error state with Try again.
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var tracksLaundry = false
    private(set) var basket = LaundryBasket(garments: [])
    /// Style Me's source when it's a suitcase, for the second scope chip.
    private(set) var sourceSuitcase: Suitcase?
    /// Which pieces show: the whole closet, or the source suitcase.
    private(set) var scope: WardrobeSource = .mainCloset
    /// The pieces she ticked, to clean together.
    private(set) var selected: Set<Garment.ID> = []
    /// Her suitcases that aren't archived, for "packed in Jose's house".
    private(set) var suitcases: [Suitcase] = []
    private var garments: [Garment] = []
    @ObservationIgnored private var loads = LoadGeneration()

    // MARK: Loading

    func load(from services: NookServices) async {
        let load = loads.begin()
        if phase != .loaded { phase = .loading }
        do {
            async let garmentList = services.closet.garments()
            async let suitcaseList = services.suitcases.suitcases()
            async let profile = services.profile.profile()
            let loaded = try await (garmentList, suitcaseList, profile)
            guard loads.isCurrent(load) else { return }
            show(garments: loaded.0, suitcases: loaded.1, profile: loaded.2)
        } catch {
            guard loads.isCurrent(load) else { return }
            if phase != .loaded { phase = .failed }
        }
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(garments: [Garment], suitcases: [Suitcase], profile: Profile) {
        self.garments = garments
        tracksLaundry = profile.preferences.tracksLaundry
        basket = LaundryBasket(garments: garments)
        self.suitcases = suitcases.filter { !$0.isArchived }
        let source = SourceChoice.shown(profile.remembered.source, among: suitcases)
        sourceSuitcase = source.suitcaseID.flatMap { id in suitcases.first { $0.id == id } }
        if sourceSuitcase == nil { scope = .mainCloset }
        // A ticked piece that's been cleaned elsewhere drops out of the selection.
        selected.formIntersection(shown.map(\.id))
        phase = .loaded
    }

    // MARK: What the screen shows

    /// The pieces in the wash in the chosen scope, in closet order (newest first).
    var shown: [Garment] {
        guard let sourceSuitcase, scope == .suitcase(sourceSuitcase.id) else { return basket.dirty }
        return basket.dirty(in: sourceSuitcase)
    }

    /// Pieces in the wash in the whole closet, kept while tracking is off too.
    var dirtyCount: Int { basket.dirty.count }

    /// How many are in the wash in each scope, for the chips.
    func count(in scope: WardrobeSource) -> Int {
        guard let id = scope.suitcaseID, let suitcase = suitcases.first(where: { $0.id == id }) else {
            return basket.dirty.count
        }
        return basket.dirty(in: suitcase).count
    }

    /// The scope's name: "Main closet" or the suitcase's.
    var scopeName: String {
        guard let sourceSuitcase, scope == .suitcase(sourceSuitcase.id) else { return SuitcasesText.mainCloset }
        return sourceSuitcase.name
    }

    /// Where a piece is: "packed in Jose's house and Weekend", or "in your closet".
    func whereItIs(_ garment: Garment, locale: Locale) -> String {
        let names = suitcases.filter { $0.contains(garment.id) }.map(\.name)
        guard !names.isEmpty else {
            return String(localized: "in your closet", bundle: .module, comment: "Laundry: where an unpacked piece is")
        }
        let list = names.formatted(.list(type: .and).locale(locale))
        return String(
            localized: "packed in \(list)", bundle: .module,
            comment: "Laundry: the suitcases a piece is packed in, as in packed in Jose's house")
    }

    func isSelected(_ id: Garment.ID) -> Bool {
        selected.contains(id)
    }

    // MARK: Choices

    func choose(scope: WardrobeSource) {
        self.scope = scope
        selected = []
    }

    func toggleSelected(_ id: Garment.ID) {
        selected.formSymmetricDifference([id])
    }

    // MARK: Changes

    /// Mark clean: the pieces still in her closet and still in the wash become clean (FR-65).
    /// Returns the ones that changed, for the toast and Undo; others are skipped.
    func markClean(_ ids: [Garment.ID], in services: NookServices) async throws(StoreError) -> [Garment.ID] {
        let cleanable = LaundryBasket.cleanable(ids, in: garments)
        guard !cleanable.isEmpty else { return [] }
        try await services.closet.setLaundry(.clean, for: cleanable)
        selected.subtract(cleanable)
        await load(from: services)
        return cleanable
    }

    /// Undo: back in the wash, but only pieces still clean, so a change made since isn't
    /// overwritten (PRD §7.3).
    func undoClean(_ ids: [Garment.ID], in services: NookServices) async throws(StoreError) {
        let fresh = try await services.closet.garments()
        let undoable = LaundryBasket.undoable(ids, in: fresh)
        if !undoable.isEmpty {
            try await services.closet.setLaundry(.dirty, for: undoable)
        }
        await load(from: services)
    }

    /// Turn on (RD-11.4): saves the setting. The marks she had come back.
    func turnOnTracking(in services: NookServices) async -> Bool {
        do {
            try await services.profile.update { $0.preferences.tracksLaundry = true }
        } catch {
            return false
        }
        await load(from: services)
        return true
    }

    /// The garment for an ID, for names in toasts and the confirmation.
    func garment(_ id: Garment.ID) -> Garment? {
        garments.first { $0.id == id }
    }
}
