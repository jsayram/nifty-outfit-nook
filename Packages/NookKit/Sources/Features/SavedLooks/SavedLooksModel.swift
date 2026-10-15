import Foundation
import Models
import Observation

/// Saved Looks (RD-08, LR-09): every look she saved, newest first, with search, piece chips and
/// colour swatches. The Looks tab works offline and uses no picture allowance (RD-08.1); the
/// Pictures tab is Phase 12b.
///
/// Loads her looks, garments and the profile once, works out each look's grid details
/// (`SavedLookItem`), then filters with the Models rule (`LookFilter`). Chips apply at once;
/// typed search waits until she pauses, as Closet's does.
@Observable
final class SavedLooksModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// A store failed. The screen shows its error state with Try again.
        case failed
    }

    enum Tab: String, Hashable, CaseIterable {
        case looks
        case pictures
    }

    var tab: Tab = .looks
    private(set) var phase: Phase = .loading
    /// Every saved look, newest saved first.
    private(set) var items: [SavedLookItem] = []
    /// The looks that match the search and filters, in the same order.
    private(set) var shown: [SavedLookItem] = []
    /// The piece chips: LR-09's six, plus Accessories when a saved look has one.
    private(set) var pieceKinds: [GarmentCategory] = SavedLooksModel.standardKinds
    /// A swatch for each colour family in her saved looks, in a fixed order.
    private(set) var colorChoices: [ColorName] = []
    /// The chips that are on and the search that's been applied.
    private(set) var filter = LookFilter()
    /// When the looks loaded, for "Last worn 3 days ago".
    private(set) var loadedAt: Date = .now
    /// The look she just deleted, so a quiet line over the looks can offer Undo for longer than
    /// the toast does. Cleared by Undo and when she leaves the tab.
    var lastRemoval: SavedLookRemoval?

    /// What's typed in the search field. Applied after `searchDelay` without typing.
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }

    let searchDelay: Duration
    /// How many times a typed search was applied, for tests of the delay.
    private(set) var searchesApplied = 0
    private var searchTask: Task<Void, Never>?

    static let standardKinds: [GarmentCategory] = [.top, .bottom, .dress, .layer, .shoes, .bag]

    init(searchDelay: Duration = .milliseconds(250)) {
        self.searchDelay = searchDelay
    }

    // MARK: Loading

    func load(from services: NookServices?, now: Date = .now) async {
        guard let services else {
            phase = .loaded
            return
        }
        if items.isEmpty { phase = .loading }
        do {
            async let looks = services.looks.looks()
            async let garments = services.closet.garments()
            show(try await looks, garments: try await garments, now: now)
        } catch {
            phase = .failed
        }
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(_ looks: [Look], garments: [Garment], now: Date) {
        loadedAt = now
        let byID = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        items =
            looks
            .filter(\.isSaved)
            .sorted { lhs, rhs in
                lhs.savedDate != rhs.savedDate ? lhs.savedDate > rhs.savedDate : lhs.id < rhs.id
            }
            .map { SavedLookItem($0, garments: byID) }

        let kinds = Set(items.flatMap { $0.filterPieces.map(\.category) })
        pieceKinds = Self.standardKinds + (kinds.contains(.accessory) ? [.accessory] : [])
        let colours = Set(items.flatMap { $0.filterPieces.flatMap(\.colors) })
        colorChoices = ColorName.allCases.filter(colours.contains)
        // A swatch whose colour is gone from every look can't be turned off any more, so drop it.
        filter.colors.formIntersection(colours)
        phase = .loaded
        refresh()
    }

    /// Undo for Delete look: the exact look back in Saved Looks, then the looks read again.
    func undoLastRemoval(using services: NookServices?, now: Date = .now) async {
        guard let removal = lastRemoval, let services else { return }
        lastRemoval = nil
        try? await removal.undo(in: services.looks)
        await load(from: services, now: now)
    }

    func item(_ id: Look.ID) -> SavedLookItem? {
        items.first { $0.id == id }
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

    /// Clear: every chip and the search (LR-09.3).
    func clearFilters() {
        searchTask?.cancel()
        filter = LookFilter()
        searchText = ""
        refresh()
    }

    /// Runs the typed search now, as when she presses Search.
    func applySearchNow() {
        searchTask?.cancel()
        applySearch()
    }

    /// Waits for a pending typed search to run. For tests.
    func settleSearch() async {
        await searchTask?.value
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            applySearch()
            return
        }
        let delay = searchDelay
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.applySearch()
        }
    }

    private func applySearch() {
        guard filter.query != searchText else { return }
        filter.query = searchText
        searchesApplied += 1
        refresh()
    }

    private func refresh() {
        let filter = filter
        shown = filter.isActive ? items.filter { $0.matches(filter) } : items
    }

    // MARK: What the screen says

    /// True when the looks have loaded and none is saved.
    var isEmpty: Bool { phase == .loaded && items.isEmpty }

    /// True when the search and filters leave no looks.
    var hasNoMatches: Bool { phase == .loaded && !items.isEmpty && shown.isEmpty }

    /// Under the title: "5 looks", or "2 of 5 looks" while filtering.
    var countText: String {
        guard phase == .loaded, !items.isEmpty else { return "" }
        let total = SavedLooksText.looks(items.count)
        return filter.isActive ? SavedLooksText.shown(shown.count, of: total) : total
    }

    /// The active filters in words, for the no-results message (LR-09.3): "Bottoms · Black · “navy”".
    var filterSummary: String {
        var parts = pieceKinds.filter { filter.categories.contains($0) }.map(\.chipTitle)
        parts += ColorName.allCases.filter { filter.colors.contains($0) }.map(\.title)
        let query = filter.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            parts.append(String(localized: "“\(query)”", bundle: .module, comment: "Typed search, in quotes"))
        }
        return parts.joined(separator: " · ")
    }
}
