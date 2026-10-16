import Foundation
import Models
import Observation

/// Suitcases (RD-09, LR-17, FR-67): her suitcases arranged by `SuitcaseShelf`, the source Style Me
/// uses, and making a new suitcase.
///
/// The order is worked out when the screen loads and stays put while she's on it, so choosing a
/// suitcase changes the tick without rows jumping about. Choosing marks it as used, so the next
/// visit shows it among the favourites (RD-09.2).
@Observable
final class SuitcasesModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// A store failed. The screen shows its error state with Try again.
        case failed
    }

    /// What happened when she chose a source.
    enum Choice: Equatable {
        /// It's the source now. `previous` is what it was, for Undo.
        case chosen(previous: WardrobeSource)
        /// An empty suitcase: the source stays as it was (`suitcases.html`'s "Pack something
        /// first"), and she's offered the suitcase to pack.
        case empty(Suitcase)
        /// It was already the source.
        case unchanged
    }

    private(set) var phase: Phase = .loading
    /// Her suitcases, arranged when the screen loaded.
    private(set) var shelf = SuitcaseShelf([])
    /// The source shown as chosen: the one she chose last, or the main closet when that
    /// suitcase has gone (PRD §7.7).
    private(set) var chosen: WardrobeSource = .mainCloset
    /// True when the source she chose last has been deleted or archived since. A line says Style
    /// Me went back to the main closet.
    private(set) var sourceWentAway = false
    /// Pieces in her closet in each suitcase. Pieces she no longer has don't count (LR-16.1).
    private(set) var pieceCounts: [Suitcase.ID: Int] = [:]
    /// Pieces in her closet.
    private(set) var closetCount = 0
    /// When it loaded, for "Used 3 days ago".
    private(set) var loadedAt: Date = .now
    /// True while a change is being saved.
    private(set) var isSaving = false
    @ObservationIgnored private var loads = LoadGeneration()

    /// Typed on All suitcases: matches suitcase names.
    var searchText = ""
    /// All suitcases' explicit filter for archived ones (RD-09.3).
    var showsArchived = false

    // MARK: Loading

    func load(from services: NookServices, now: Date = .now) async {
        let load = loads.begin()
        if phase != .loaded { phase = .loading }
        do {
            async let suitcaseList = services.suitcases.suitcases()
            async let garmentList = services.closet.garments()
            async let profile = services.profile.profile()
            let loaded = try await (suitcaseList, garmentList, profile)
            guard loads.isCurrent(load) else { return }
            show(suitcases: loaded.0, garments: loaded.1, profile: loaded.2, now: now)
        } catch {
            guard loads.isCurrent(load) else { return }
            if phase != .loaded { phase = .failed }
        }
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(suitcases: [Suitcase], garments: [Garment], profile: Profile, now: Date) {
        loadedAt = now
        shelf = SuitcaseShelf(suitcases)
        let inCloset = garments.filter(\.isInCloset)
        closetCount = inCloset.count
        let ids = Set(inCloset.map(\.id))
        pieceCounts = Dictionary(
            uniqueKeysWithValues: suitcases.map { ($0.id, $0.garmentIDs.count(where: ids.contains)) })
        let remembered = profile.remembered.source
        chosen = SourceChoice.shown(remembered, among: suitcases)
        sourceWentAway = chosen != remembered
        phase = .loaded
    }

    // MARK: What the screen shows

    var favorites: [Suitcase] { shelf.favorites }

    /// Every suitcase that isn't a favourite, in the shelf's order, for All suitcases.
    var others: [Suitcase] { Array(shelf.all.dropFirst(shelf.favorites.count)) }

    var hasSuitcases: Bool { !shelf.all.isEmpty || !shelf.archived.isEmpty }

    /// All suitcases with the search applied: favourites first, then the rest, then archived
    /// ones only while their filter is on (RD-09.3).
    func matching(_ suitcases: [Suitcase]) -> [Suitcase] {
        let words = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return suitcases }
        return suitcases.filter { suitcase in
            words.allSatisfy { suitcase.name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    func pieceCount(of suitcase: Suitcase) -> Int {
        pieceCounts[suitcase.id] ?? 0
    }

    func isChosen(_ source: WardrobeSource) -> Bool {
        chosen == source
    }

    func suitcase(_ id: Suitcase.ID) -> Suitcase? {
        (shelf.all + shelf.archived).first { $0.id == id }
    }

    /// The name of a source, for toasts.
    func name(of source: WardrobeSource) -> String {
        source.suitcaseID.flatMap { suitcase($0)?.name } ?? SuitcasesText.mainCloset
    }

    /// Every suitcase name, for checking a new one is unique.
    var allSuitcases: [Suitcase] { shelf.all + shelf.archived }

    // MARK: Changes

    /// Makes `source` the one Style Me uses (FR-67): remembered for next time, and a suitcase is
    /// marked as used, so it's a favourite next time (RD-09.2). An empty suitcase isn't chosen.
    func choose(_ source: WardrobeSource, in services: NookServices, now: Date = .now) async throws(StoreError)
        -> Choice
    {
        if let id = source.suitcaseID, let suitcase = suitcase(id), pieceCount(of: suitcase) == 0 {
            return .empty(suitcase)
        }
        guard source != chosen else { return .unchanged }
        let previous = chosen
        isSaving = true
        defer { isSaving = false }
        try await services.profile.update { $0.remembered.source = source }
        if let id = source.suitcaseID {
            try await services.suitcases.markUsed(id, at: now)
        }
        chosen = source
        sourceWentAway = false
        return .chosen(previous: previous)
    }

    /// "+ Add a suitcase" (LR-17): makes it, and it shows at once (LR-17.2).
    func create(name: String, icon: SuitcaseIcon, in services: NookServices, now: Date = .now)
        async throws(StoreError) -> Suitcase
    {
        isSaving = true
        defer { isSaving = false }
        let suitcase = try await services.suitcases.create(name: name, icon: icon, at: now)
        await load(from: services, now: now)
        return suitcase
    }

    /// Why a typed name can't be used, or `nil` when it can.
    func nameProblem(_ text: String, renaming: Suitcase.ID? = nil) -> NameProblem? {
        do {
            _ = try NameRules.suitcaseName(text, among: allSuitcases, renaming: renaming)
            return nil
        } catch {
            return error
        }
    }
}
