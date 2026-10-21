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
///
/// The Looks tab has a scope (Phase 21c, decided 21 October 2026): Saved is her saved looks, All
/// is those plus every Style Me result she kept but didn't save (LR-06.4), in one list. Search and
/// the chips work the same in both; on Saved, a line at the end says how many more looks the same
/// search and chips find in All (`moreInAll`).
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

    /// Which looks the Looks tab lists. It starts on Saved, and the screen puts it back there each
    /// time she leaves the tab.
    enum Scope: String, Hashable, CaseIterable {
        /// Only her saved looks.
        case saved
        /// Her saved looks and every Style Me result she kept but didn't save (LR-06.4).
        case all
    }

    var tab: Tab = .looks {
        didSet {
            guard tab != oldValue else { return }
            updateChoices()
        }
    }

    /// Saved or All. Search and the chips stay as they are; the swatches follow the scope.
    var scope: Scope = .saved {
        didSet {
            guard scope != oldValue else { return }
            updateChoices()
        }
    }

    private(set) var phase: Phase = .loading
    /// Every saved look, newest saved first.
    private(set) var items: [SavedLookItem] = []
    /// Every Style Me result she kept but didn't save, newest first (LR-06.4, Phase 21c).
    private(set) var unsavedItems: [SavedLookItem] = []
    /// Saved and unsaved looks in one list, newest made first. Saving a look doesn't move it
    /// here, so it changes where it is.
    private(set) var allItems: [SavedLookItem] = []
    /// The looks the scope lists that match the search and filters, in the list's order.
    private(set) var shown: [SavedLookItem] = []
    /// On Saved: how many unsaved looks the search and chips match too. Zero when none is set,
    /// and on All.
    private(set) var moreInAll = 0
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
    /// Looks being saved from the grid, so a second tap on the same one does nothing.
    @ObservationIgnored private var saving: Set<Look.ID> = []

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
        allItems =
            looks
            .map { SavedLookItem($0, garments: byID) }
            .sorted { lhs, rhs in
                lhs.look.createdAt != rhs.look.createdAt ? lhs.look.createdAt > rhs.look.createdAt : lhs.id < rhs.id
            }
        deriveLists()
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

    /// The saved list (newest saved first) and the unsaved list (newest made first), from `allItems`.
    private func deriveLists() {
        items =
            allItems
            .filter { $0.isSaved }
            .sorted { lhs, rhs in
                lhs.look.savedDate != rhs.look.savedDate ? lhs.look.savedDate > rhs.look.savedDate : lhs.id < rhs.id
            }
        unsavedItems = allItems.filter { !$0.isSaved }
    }

    /// Puts a look that just changed (saved from the grid, or put back by Undo) where it belongs.
    /// Its place in `allItems` doesn't change, so the list doesn't move under her.
    private func place(_ look: Look) {
        looksByID[look.id] = look
        let item = SavedLookItem(look, garments: garmentsByID)
        if let index = allItems.firstIndex(where: { $0.id == look.id }) {
            allItems[index] = item
        } else {
            allItems.append(item)
            allItems.sort { lhs, rhs in
                lhs.look.createdAt != rhs.look.createdAt ? lhs.look.createdAt > rhs.look.createdAt : lhs.id < rhs.id
            }
        }
        deriveLists()
        if picturesPhase == .loaded { buildPictureItems() }
        updateChoices()
    }

    // MARK: Save look, from the grid

    /// Save look on a look that isn't saved, from the grid on All: it joins Saved Looks, named as
    /// Your looks names a saved result (LR-08), and changes where it is. Returns the look before,
    /// for Undo, or `nil` when it's already saved or being saved.
    func save(
        _ id: Look.ID, locale: Locale, using services: NookServices, now: Date = .now
    ) async throws(StoreError) -> Look? {
        guard let before = looksByID[id], !before.isSaved, saving.insert(id).inserted else { return nil }
        defer { saving.remove(id) }
        var saved = before
        saved.isSaved = true
        saved.savedAt = now
        saved.name = YourLooksText.name(for: before, occasion: before.occasion, garments: garmentsByID, locale: locale)
        try await services.looks.save(saved)
        place(saved)
        return before
    }

    /// Undo for Save look: the exact look before, unsaved again.
    func undoSave(_ before: Look, using services: NookServices) async throws(StoreError) {
        try await services.looks.save(before)
        place(before)
    }

    /// The chips and swatches for what the tabs hold, so a chip never disappears when she switches
    /// tab. The Looks tab on All adds what her unsaved looks have; Saved and Pictures don't, so
    /// a swatch there always finds something. A chip or swatch that's on stays on show, so she
    /// can always turn it off.
    private func updateChoices() {
        let shownLooks = tab == .looks && scope == .all ? allItems : items
        let pictures = pictureItems.flatMap(\.filterLook.filterPieces)
        let pieces = shownLooks.flatMap(\.filterPieces) + pictures
        let kinds = Set(pieces.map(\.category))
        pieceKinds =
            Self.standardKinds
            + (kinds.contains(.accessory) || filter.categories.contains(.accessory) ? [.accessory] : [])
        let colours = Set(pieces.flatMap(\.colors))
        // A swatch whose colour is gone from every look can't be turned off any more, so drop it.
        let everyColour = Set(allItems.flatMap(\.filterPieces).flatMap(\.colors) + pictures.flatMap(\.colors))
        filter.colors.formIntersection(everyColour)
        colorChoices = ColorName.allCases.filter { colours.contains($0) || filter.colors.contains($0) }
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

    /// A saved look's item. A look she hasn't saved has none: find it in `unsavedItems`.
    func item(_ id: Look.ID) -> SavedLookItem? {
        items.first { $0.id == id }
    }

    func pictureItem(_ id: TryOnPicture.ID) -> SavedPictureItem? {
        pictureItems.first { $0.id == id }
    }

    // MARK: Filters

    func toggle(_ kind: GarmentCategory) {
        filter.categories.formSymmetricDifference([kind])
        updateChoices()
    }

    func toggle(_ color: ColorName) {
        filter.colors.formSymmetricDifference([color])
        // A swatch that was only on show because it was on goes when it's turned off.
        updateChoices()
    }

    /// Clear: every chip and the search (LR-09.3).
    func clearFilters() {
        search.cancel()
        filter = LookFilter()
        searchText = ""
        updateChoices()
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
        let listed = scopeItems
        shown = filter.isActive ? listed.filter { $0.matches(filter) } : listed
        // The nudge on Saved needs a search or a chip: with neither, every unsaved look "matches".
        moreInAll = scope == .saved && filter.isActive ? unsavedItems.count { $0.matches(filter) } : 0
        shownPictures = filter.isActive ? pictureItems.filter { $0.matches(filter) } : pictureItems
    }

    // MARK: What the screen says

    /// The looks the scope lists, before the search and filters.
    private var scopeItems: [SavedLookItem] {
        scope == .all ? allItems : items
    }

    /// True when the looks have loaded and the scope lists none: nothing saved yet on Saved,
    /// no looks at all on All.
    var isEmpty: Bool { phase == .loaded && scopeItems.isEmpty }

    /// True when the search and filters leave no looks in the scope.
    var hasNoMatches: Bool { phase == .loaded && !scopeItems.isEmpty && shown.isEmpty }

    /// True when she has Style Me results she didn't save, which only All lists.
    var hasUnsaved: Bool { !unsavedItems.isEmpty }

    /// True for a look she hasn't saved, which opens from All with Save look (LR-06.4).
    func isNotSaved(_ id: Look.ID) -> Bool {
        unsavedItems.contains { $0.id == id }
    }

    /// True when the pictures have loaded and there are none.
    var hasNoPictures: Bool { picturesPhase == .loaded && pictureItems.isEmpty }

    /// True when the search and filters leave no pictures.
    var picturesHaveNoMatches: Bool {
        picturesPhase == .loaded && !pictureItems.isEmpty && shownPictures.isEmpty
    }

    /// Under the title: "5 looks" on Saved, "8 looks, 3 not saved" on All.
    var headerCountText: String {
        guard phase == .loaded, !scopeItems.isEmpty else { return "" }
        let total = SavedLooksText.looks(scopeItems.count)
        guard scope == .all, !unsavedItems.isEmpty else { return total }
        return SavedLooksText.withUnsaved(total, unsaved: unsavedItems.count)
    }

    /// On the count line: "5 looks", or "2 of 5 looks" while filtering, out of the scope's looks.
    var countText: String {
        guard phase == .loaded, !scopeItems.isEmpty else { return "" }
        let total = SavedLooksText.looks(scopeItems.count)
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
