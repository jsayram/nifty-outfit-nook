import Foundation
import Models
import Observation

/// Which pieces a closet-style list shows, when it isn't Closet itself (Phase 11): See all in
/// Swap a piece, and the piece picker in Make your own look. They reuse Closet's search, filters
/// and grid over a chosen set of pieces.
struct PieceScope: Equatable {
    /// The pieces to show, in this order. Pieces not listed are left out.
    var garmentIDs: [Garment.ID]
    /// A short mark under a piece's name, such as "May not match" (LR-07.3).
    var notes: [Garment.ID: String] = [:]
    /// Every piece is this kind (See all tops), so the piece chips aren't shown.
    var fixedKind: GarmentCategory?
}

/// What Closet shows, and its search and filters (RD-13, LR-09, LR-11, RD-11).
///
/// Loads her garments, suitcases and Preferences once, works out each piece's grid details
/// (`ClosetItem`), then filters with the Models rule (`GarmentFilter`). Chips apply at once;
/// typed search waits until she pauses (`SearchDebouncer`), so a long closet isn't filtered on every
/// letter. Clearing the field or pressing Search applies straight away.
@Observable
final class ClosetModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// A store failed. The screen shows its error state with Try again.
        case failed
    }

    private(set) var phase: Phase = .loading
    /// Every piece in her closet (`Garment.isInCloset`), newest first.
    private(set) var items: [ClosetItem] = []
    /// The pieces that match the search and filters, in the same order.
    private(set) var shown: [ClosetItem] = []
    /// Her suitcases that aren't archived, by name, for the Suitcase filter (LR-11).
    private(set) var suitcases: [Suitcase] = []
    /// Laundry tracking (RD-11). Off: no Dirty chip, no badges, no Laundry entry.
    private(set) var tracksLaundry = false
    /// Pieces in her closet marked as in the wash, while tracking is on.
    private(set) var dirtyCount = 0
    /// Pieces in Recently deleted (LR-16).
    private(set) var deletedCount = 0
    /// The piece chips: LR-09's six, plus Accessories when she has any.
    private(set) var pieceKinds: [GarmentCategory] = ClosetModel.standardKinds
    /// A swatch for each colour family in her closet, in a fixed order.
    private(set) var colorChoices: [ColorName] = []
    /// The chips that are on and the search that's been applied.
    private(set) var filter = GarmentFilter()
    /// When the closet loaded, for "Last worn 3 days ago".
    private(set) var loadedAt: Date = .now
    /// An unsaved Add a piece or Edit draft, offered as "Continue where you left off?" (Phase 7b).
    private(set) var draft: GarmentDraft?

    /// What's typed in the search field. Applied once typing pauses (`SearchDebouncer`).
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }

    /// How many times a typed search was applied, for tests of the delay.
    private(set) var searchesApplied = 0
    @ObservationIgnored private let search: SearchDebouncer
    @ObservationIgnored private var loads = LoadGeneration()

    private var garments: [Garment] = []
    private var itemsByID: [Garment.ID: ClosetItem] = [:]
    private var allSuitcases: [Suitcase] = []

    static let standardKinds: [GarmentCategory] = [.top, .bottom, .dress, .layer, .shoes, .bag]

    /// A chosen set of pieces instead of her whole closet (`PieceScope`). `nil` for Closet.
    let scope: PieceScope?

    init(searchDelay: Duration = .milliseconds(250), scope: PieceScope? = nil) {
        search = SearchDebouncer(delay: searchDelay)
        self.scope = scope
    }

    /// The Dirty chip, only on Closet itself while tracking is on. A scoped list only holds
    /// pieces she can wear now, so it has nothing in the wash to find.
    var showsLaundryFilter: Bool { tracksLaundry && scope == nil }

    // MARK: Loading

    /// Sets one piece chip on its own, as a picker opening on a kind does.
    func showOnly(_ kind: GarmentCategory) {
        filter.categories = [kind]
        refresh()
    }

    /// Reads her pieces, suitcases, Preferences and any draft. A load that an overlapping newer
    /// one has overtaken shows nothing (`LoadGeneration`).
    func load(from services: NookServices, now: Date = .now) async {
        let load = loads.begin()
        if items.isEmpty { phase = .loading }
        let loaded: ([Garment], [Suitcase], Profile)
        do {
            async let garmentList = services.closet.garments()
            async let suitcaseList = services.suitcases.suitcases()
            async let profile = services.profile.profile()
            loaded = try await (garmentList, suitcaseList, profile)
        } catch {
            guard loads.isCurrent(load) else { return }
            phase = .failed
            return
        }
        guard loads.isCurrent(load) else { return }
        show(loaded.0, suitcases: loaded.1, profile: loaded.2, now: now)
        let drafts = (try? await services.drafts.drafts()) ?? []
        guard loads.isCurrent(load) else { return }
        offerDraft(from: drafts)
    }

    /// The most recent draft with changes. A draft for a piece that's no longer in her closet
    /// isn't offered (it stays, in case Undo brings the piece back). A draft store that can't
    /// be read just means nothing is offered.
    private func offerDraft(from all: [GarmentDraft]) {
        draft = all.first { draft in
            guard draft.hasChanges else { return false }
            switch draft.target {
            case .newPiece: return true
            case .garment(let id): return itemsByID[id] != nil
            }
        }
    }

    /// Discard on "Continue where you left off?".
    func discardDraft(in drafts: any DraftStore) async {
        guard let draft else { return }
        self.draft = nil
        try? await drafts.discard(draft.target)
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(_ all: [Garment], suitcases allSuitcases: [Suitcase], profile: Profile, now: Date) {
        loadedAt = now
        tracksLaundry = profile.preferences.tracksLaundry
        if let scope {
            let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            garments = scope.garmentIDs.compactMap { byID[$0] }.filter(\.isInCloset)
        } else {
            garments = all.filter(\.isInCloset)
        }
        deletedCount = all.count(where: \.isDeleted)
        self.allSuitcases = allSuitcases
        suitcases = allSuitcases.filter { !$0.isArchived }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var names: [Garment.ID: [String]] = [:]
        for suitcase in suitcases {
            for id in suitcase.garmentIDs { names[id, default: []].append(suitcase.name) }
        }
        items = garments.map {
            ClosetItem(
                $0, suitcaseNames: names[$0.id] ?? [], tracksLaundry: tracksLaundry, note: scope?.notes[$0.id])
        }
        itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        dirtyCount = items.count(where: \.isDirty)

        let kinds = Set(garments.map(\.category))
        if scope?.fixedKind != nil {
            pieceKinds = []
        } else if scope != nil {
            // A picker offers the kinds it holds.
            pieceKinds = GarmentCategory.allCases.filter(kinds.contains)
        } else {
            pieceKinds = Self.standardKinds + (kinds.contains(.accessory) ? [.accessory] : [])
        }
        let colours = Set(garments.flatMap(\.colors))
        colorChoices = ColorName.allCases.filter { colours.contains($0) }

        // Drop choices the new data can't satisfy: a suitcase that's gone, the Dirty chip
        // after tracking was turned off.
        if case .suitcase(let id) = filter.packing, !suitcases.contains(where: { $0.id == id }) {
            filter.packing = .any
        }
        if !tracksLaundry { filter.laundry = nil }
        phase = .loaded
        refresh()
    }

    // MARK: Filters

    func toggle(_ kind: GarmentCategory) {
        filter.categories.formSymmetricDifference([kind])
        refresh()
    }

    func toggle(_ color: ColorName) {
        filter.colors.formSymmetricDifference([color])
        refresh()
    }

    func setPacking(_ packing: GarmentFilter.Packing) {
        filter.packing = packing
        refresh()
    }

    /// The Dirty chip. Does nothing while tracking is off, since the chip isn't there (RD-11.1).
    func toggleDirty() {
        guard tracksLaundry else { return }
        filter.laundry = filter.laundry == nil ? .dirty : nil
        refresh()
    }

    /// Clear: every chip and the search (LR-09.3).
    func clearFilters() {
        search.cancel()
        filter = GarmentFilter()
        searchText = ""
        refresh()
    }

    /// Runs the typed search now, as when she presses Search.
    func applySearchNow() {
        search.cancel()
        applySearch()
    }

    /// Waits for a pending typed search to run. For tests.
    func settleSearch() async {
        await search.settle()
    }

    private func scheduleSearch() {
        search.schedule(searchText) { [weak self] in self?.applySearch() }
    }

    private func applySearch() {
        guard filter.query != searchText else { return }
        filter.query = searchText
        searchesApplied += 1
        refresh()
    }

    private func refresh() {
        guard filter.isActive else {
            shown = items
            return
        }
        let categoryWords = Self.categoryWords
        let colorWords = Self.colorWords
        let matching = filter.apply(to: garments, suitcases: allSuitcases) { garment in
            (categoryWords[garment.category] ?? []) + garment.colors.compactMap { colorWords[$0] }
        }
        shown = matching.compactMap { itemsByID[$0.id] }
    }

    /// The localized words a piece answers to in search besides its own text: its kind
    /// ("Shoes", "Shoe") and its colours ("Black").
    private static let categoryWords: [GarmentCategory: [String]] = Dictionary(
        uniqueKeysWithValues: GarmentCategory.allCases.map { ($0, [$0.chipTitle, $0.singularTitle]) })
    private static let colorWords: [ColorName: String] = Dictionary(
        uniqueKeysWithValues: ColorName.allCases.map { ($0, $0.title) })

    // MARK: What the screen says

    /// True when the closet has loaded with nothing in it.
    var isEmpty: Bool { phase == .loaded && items.isEmpty }

    /// True when filters or search leave no pieces.
    var hasNoMatches: Bool { phase == .loaded && !items.isEmpty && shown.isEmpty }

    /// The selected suitcase's name, for the Suitcase chip.
    var packingTitle: String? {
        switch filter.packing {
        case .any: nil
        case .inASuitcase:
            String(localized: "In a suitcase", bundle: .module, comment: "Suitcase filter choice")
        case .notPacked:
            String(localized: "Not packed", bundle: .module, comment: "Suitcase filter choice")
        case .suitcase(let id): suitcases.first { $0.id == id }?.name
        }
    }

    /// Under the title: "17 pieces", or "5 of 17 pieces" while filtering.
    var countText: String {
        if phase != .loaded {
            return ""
        }
        if items.isEmpty {
            return String(localized: "No pieces yet", bundle: .module, comment: "Closet count when it's empty")
        }
        let total = String(
            localized: "\(items.count) pieces", bundle: .module, comment: "Source plate: how many pieces the source has"
        )
        if filter.isActive {
            return String(
                localized: "\(shown.count) of \(total)", bundle: .module,
                comment: "Closet count while filtering: how many match, of how many pieces, as in 5 of 17 pieces")
        }
        return total
    }

    /// The active filters in words, for the no-results message (LR-09.3): "Shoes · Black · “navy”".
    var filterSummary: String {
        var parts = pieceKinds.filter { filter.categories.contains($0) }.map(\.chipTitle)
        parts += ColorName.allCases.filter { filter.colors.contains($0) }.map(\.title)
        if let packingTitle { parts.append(packingTitle) }
        if filter.laundry == .dirty {
            parts.append(String(localized: "Dirty", bundle: .module, comment: "Laundry filter chip"))
        }
        let query = filter.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            parts.append(String(localized: "“\(query)”", bundle: .module, comment: "Typed search, in quotes"))
        }
        return parts.joined(separator: " · ")
    }
}
