import Foundation
import Models
import Observation

/// Saved Looks (RD-08, LR-09): every look she saved, newest first, and on the Pictures tab every
/// try-on picture, newest first (Phase 12b), with search, piece chips and colour swatches. The
/// Looks tab works offline and uses no picture allowance (RD-08.1).
///
/// Loads her looks, garments and pictures once, works out each look's and picture's grid details
/// (`SavedLookItem`, `SavedPictureItem`), then filters with the Models rule (`LookFilter`). Chips
/// apply at once; typed search waits until she pauses, as Closet's does.
///
/// The search and the chips are shared by both tabs, so "navy" stays set when she switches to
/// Pictures. On Pictures they match the look each picture came from (RD-08.3).
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
    /// The Pictures tab: loading, loaded or failed, apart from the looks, so the Looks tab still
    /// works when pictures can't be read.
    private(set) var picturesPhase: Phase = .loading
    /// Every try-on picture, newest first.
    private(set) var pictureItems: [SavedPictureItem] = []
    /// The pictures that match the search and filters, in the same order.
    private(set) var shownPictures: [SavedPictureItem] = []
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
    /// The picture she just deleted, for the same line over the pictures.
    var lastPictureRemoval: PictureRemoval?

    private var looksByID: [Look.ID: Look] = [:]
    private var garmentsByID: [Garment.ID: Garment] = [:]
    private var pictures: [TryOnPicture] = []

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

    static let standardKinds: [GarmentCategory] = [.top, .bottom, .dress, .layer, .shoes, .bag]

    init(searchDelay: Duration = .milliseconds(250)) {
        search = SearchDebouncer(delay: searchDelay)
    }

    // MARK: Loading

    /// Reads the looks, garments and pictures. A load that an overlapping newer one has
    /// overtaken shows nothing (`LoadGeneration`).
    func load(from services: NookServices, now: Date = .now) async {
        let load = loads.begin()
        if items.isEmpty { phase = .loading }
        if pictureItems.isEmpty { picturesPhase = .loading }
        let looks: [Look]
        let garments: [Garment]
        do {
            async let lookList = services.looks.looks()
            async let garmentList = services.closet.garments()
            (looks, garments) = try await (lookList, garmentList)
        } catch {
            guard loads.isCurrent(load) else { return }
            phase = .failed
            picturesPhase = .failed
            return
        }
        guard loads.isCurrent(load) else { return }
        show(looks, garments: garments, now: now)
        do {
            let pictures = try await services.pictures.pictures()
            guard loads.isCurrent(load) else { return }
            showPictures(pictures)
        } catch {
            guard loads.isCurrent(load) else { return }
            picturesPhase = .failed
        }
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(_ looks: [Look], garments: [Garment], now: Date) {
        loadedAt = now
        let byID = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        garmentsByID = byID
        looksByID = Dictionary(looks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        items =
            looks
            .filter(\.isSaved)
            .sorted { lhs, rhs in
                lhs.savedDate != rhs.savedDate ? lhs.savedDate > rhs.savedDate : lhs.id < rhs.id
            }
            .map { SavedLookItem($0, garments: byID) }
        phase = .loaded
        if picturesPhase == .loaded {
            // The looks changed, so where each picture's look is may have too.
            buildPictureItems()
        }
        updateChoices()
    }

    /// Sets the pictures, after `show` has set the looks and garments they link to.
    func showPictures(_ pictures: [TryOnPicture]) {
        self.pictures = TryOnLinks.newestFirst(pictures)
        buildPictureItems()
        picturesPhase = .loaded
        updateChoices()
    }

    private func buildPictureItems() {
        pictureItems = pictures.map { SavedPictureItem($0, looks: looksByID, garments: garmentsByID) }
    }

    /// The chips and swatches for what both tabs hold, so a chip never disappears when she
    /// switches tab.
    private func updateChoices() {
        let pieces = items.flatMap(\.filterPieces) + pictureItems.flatMap(\.filterLook.filterPieces)
        let kinds = Set(pieces.map(\.category))
        pieceKinds = Self.standardKinds + (kinds.contains(.accessory) ? [.accessory] : [])
        let colours = Set(pieces.flatMap(\.colors))
        colorChoices = ColorName.allCases.filter(colours.contains)
        // A swatch whose colour is gone from every look can't be turned off any more, so drop it.
        filter.colors.formIntersection(colours)
        refresh()
    }

    /// Undo for Delete look: the exact look back in Saved Looks, then the looks read again.
    func undoLastRemoval(using services: NookServices, now: Date = .now) async {
        guard let removal = lastRemoval else { return }
        lastRemoval = nil
        try? await removal.undo(in: services.looks)
        await load(from: services, now: now)
    }

    /// Undo for Delete picture: the same picture back, linked to its look as before.
    func undoLastPictureRemoval(using services: NookServices, now: Date = .now) async {
        guard let removal = lastPictureRemoval else { return }
        lastPictureRemoval = nil
        try? await removal.undo(in: services.pictures)
        await load(from: services, now: now)
    }

    func item(_ id: Look.ID) -> SavedLookItem? {
        items.first { $0.id == id }
    }

    func pictureItem(_ id: TryOnPicture.ID) -> SavedPictureItem? {
        pictureItems.first { $0.id == id }
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
        search.cancel()
        filter = LookFilter()
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
        let filter = filter
        shown = filter.isActive ? items.filter { $0.matches(filter) } : items
        shownPictures = filter.isActive ? pictureItems.filter { $0.matches(filter) } : pictureItems
    }

    // MARK: What the screen says

    /// True when the looks have loaded and none is saved.
    var isEmpty: Bool { phase == .loaded && items.isEmpty }

    /// True when the search and filters leave no looks.
    var hasNoMatches: Bool { phase == .loaded && !items.isEmpty && shown.isEmpty }

    /// True when the pictures have loaded and there are none.
    var hasNoPictures: Bool { picturesPhase == .loaded && pictureItems.isEmpty }

    /// True when the search and filters leave no pictures.
    var picturesHaveNoMatches: Bool {
        picturesPhase == .loaded && !pictureItems.isEmpty && shownPictures.isEmpty
    }

    /// Under the title: "5 looks", or "2 of 5 looks" while filtering.
    var countText: String {
        guard phase == .loaded, !items.isEmpty else { return "" }
        let total = SavedLooksText.looks(items.count)
        return filter.isActive ? SavedLooksText.shown(shown.count, of: total) : total
    }

    /// The same for the Pictures tab: "3 pictures", or "1 of 3 pictures".
    var picturesCountText: String {
        guard picturesPhase == .loaded, !pictureItems.isEmpty else { return "" }
        let total = TryOnText.pictures(pictureItems.count)
        return filter.isActive ? SavedLooksText.shown(shownPictures.count, of: total) : total
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
