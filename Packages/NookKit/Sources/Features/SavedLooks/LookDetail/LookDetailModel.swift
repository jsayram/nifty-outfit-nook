import Foundation
import Models
import Observation

/// One saved look, opened from Saved Looks or a frame on the Home shelf (Phase 12a).
///
/// It shows the look large with its pieces and facts, and offers Wear today (LR-10), Swap a piece
/// (LR-08), Try it on (a stand-in until 12b), Rename and Delete look. Every change is one store
/// call and comes back with Undo. Nothing here sends a request or uses a picture allowance
/// (RD-08.1).
///
/// Swap a piece changes this saved look in place: same ID, name and saved date, so it stays where
/// it is in Saved Looks and on the shelf. Undo puts back exactly the look before (LR-08.2).
@Observable
final class LookDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// A store failed. The screen shows its error state with Try again.
        case failed
        /// The look isn't saved any more (deleted on another screen).
        case missing
    }

    let lookID: Look.ID
    private(set) var phase: Phase = .loading
    private(set) var look: Look?
    /// Every garment she has, by ID, including pieces that left her closet.
    private(set) var garments: [Garment.ID: Garment] = [:]
    /// Every look, for the outfits she wore lately (Swap's "Worn together lately").
    private(set) var looks: [Look] = []
    private(set) var suitcases: [Suitcase] = []
    private(set) var profile = Profile()

    private var services: NookServices?
    private let now: () -> Date
    private let calendar: Calendar
    private let makeLookID: () -> Look.ID

    init(
        lookID: Look.ID,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current,
        makeLookID: @escaping () -> Look.ID = { .random() }
    ) {
        self.lookID = lookID
        self.now = now
        self.calendar = calendar
        self.makeLookID = makeLookID
    }

    // MARK: Loading

    /// Reads the look and what it needs. Runs again each time the screen appears, so a piece
    /// changed on garment detail shows when she comes back.
    func load(from services: NookServices?) async {
        self.services = services
        guard let services else {
            phase = .missing
            return
        }
        if look == nil { phase = .loading }
        do {
            async let lookList = services.looks.looks()
            async let garmentList = services.closet.garments()
            async let suitcaseList = services.suitcases.suitcases()
            async let profile = services.profile.profile()
            let (looks, garments, suitcases) = try await (lookList, garmentList, suitcaseList)
            show(looks: looks, garments: garments, suitcases: suitcases, profile: try await profile)
        } catch {
            phase = .failed
        }
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(looks: [Look], garments: [Garment], suitcases: [Suitcase], profile: Profile) {
        self.looks = looks
        self.garments = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.suitcases = suitcases
        self.profile = profile
        look = looks.first { $0.id == lookID && $0.isSaved }
        phase = look == nil ? .missing : .loaded
    }

    // MARK: What the screen shows

    var content: LookBundleContent? {
        look.map { LookBundleContent(look: $0, garments: garments) }
    }

    var name: String {
        guard let look else { return "" }
        return look.name ?? SavedLooksText.unnamed(occasion: look.occasion?.title)
    }

    /// Her pieces that were deleted for good, so there's nothing left to show (PRD §7.4).
    var goneCount: Int {
        look?.garmentIDs.count { garments[$0] == nil } ?? 0
    }

    /// The pieces that left her closet, faded with Swap it (LR-16.4).
    var removedPieces: [LookBundlePiece] {
        content?.removed ?? []
    }

    /// "Main closet", or the suitcase's name. A suitcase she has since deleted reads as Main
    /// closet, which is where Swap looks too.
    var sourceName: String {
        guard let id = look?.source.suitcaseID, let suitcase = suitcases.first(where: { $0.id == id }) else {
            return String(localized: "Main closet", bundle: .module, comment: "Source plate: the whole closet")
        }
        return suitcase.name
    }

    /// The facts under the name: "Office · Saved 28 Aug · Last worn 5 days ago · From Weekend".
    func facts(locale: Locale) -> [String] {
        guard let look else { return [] }
        let now = now()
        var facts: [String] = []
        if let occasion = look.occasion { facts.append(occasion.title) }
        facts.append(LookDetailText.saved(look.savedDate, now: now, calendar: calendar, locale: locale))
        if let lastWorn = look.lastWorn {
            facts.append(LastWornText.describe(lastWorn, now: now, calendar: calendar, locale: locale))
        }
        if look.source.isSuitcase {
            facts.append(LookDetailText.from(sourceName))
        }
        return facts
    }

    /// True when she chose Wear today for this look today.
    var isWornToday: Bool {
        let today = now()
        return look?.wornOn.contains { calendar.isDate($0, inSameDayAs: today) } ?? false
    }

    // MARK: Rename

    /// What's wrong with a new name, or `nil` when it can be saved (`NameRules.lookName`).
    func renameProblem(_ text: String) -> NameProblem? {
        do {
            _ = try NameRules.lookName(text)
            return nil
        } catch {
            return error
        }
    }

    /// Renames the look. The name is trimmed; a name with a problem is refused.
    func rename(to text: String) async throws(StoreError) {
        guard let services, let look else { throw .unavailable }
        let name: String
        do {
            name = try NameRules.lookName(text)
        } catch {
            throw .invalidName(error)
        }
        let updated = try await services.looks.update(look.id) { $0.name = name }
        replace(updated)
    }

    // MARK: Wear today

    /// What Wear today recorded, so Undo can take exactly that back (LR-10.1).
    struct Wear: Equatable {
        let lookID: Look.ID
        /// Her pieces in her closet, which got the wear too. Pieces she no longer has didn't.
        let garmentIDs: [Garment.ID]
        let date: Date
    }

    /// Wear today: records today on the look and its pieces still in her closet. Laundry is
    /// untouched (LR-10, option A).
    func wearToday() async throws(StoreError) -> Wear {
        guard let services, let look else { throw .unavailable }
        let wear = Wear(lookID: look.id, garmentIDs: wornPieces(of: look), date: now())
        try await services.looks.recordWear(of: wear.lookID, on: wear.date)
        try await services.closet.recordWear(of: wear.garmentIDs, on: wear.date)
        await reload()
        return wear
    }

    /// Undo for Wear today, or taking today's wear off again.
    func undo(_ wear: Wear) async throws(StoreError) {
        guard let services else { throw .unavailable }
        try await services.looks.removeWear(of: wear.lookID, on: wear.date)
        try await services.closet.removeWear(of: wear.garmentIDs, on: wear.date)
        await reload()
    }

    /// Takes today's wear off the look and its pieces, when she tapped Worn today again.
    func removeTodaysWear() async throws(StoreError) -> Wear {
        guard let look else { throw .unavailable }
        let wear = Wear(lookID: look.id, garmentIDs: wornPieces(of: look), date: now())
        try await undo(wear)
        return wear
    }

    private func wornPieces(of look: Look) -> [Garment.ID] {
        look.garmentIDs.filter { garments[$0]?.isInCloset ?? false }
    }

    // MARK: Swap a piece

    /// What Swap a piece needs for this look, from what the screen already loaded, so Swap reads
    /// nothing and sends nothing (LR-07.1). Options come from the look's source, as on results;
    /// a saved look keeps no weather, so the weather doesn't rank them.
    func swapSetup() -> SwapSetup? {
        guard let look else { return nil }
        let suitcase = look.source.suitcaseID.flatMap { id in suitcases.first { $0.id == id } }
        let source: WardrobeSource = suitcase == nil ? .mainCloset : look.source
        let date = now()
        let recent = WearRules.recentCombinations(
            in: looks, categories: garments.mapValues(\.category), window: profile.preferences.repeatWindow,
            now: date, calendar: calendar)
        return SwapSetup(
            look: look,
            simple: nil,
            garments: garments,
            suitcases: suitcases,
            situation: SwapSituation(
                source: source,
                members: suitcase.map(\.garmentIDs),
                occasion: look.occasion,
                fit: profile.usualFit?.matchingFit,
                tracksLaundry: profile.preferences.tracksLaundry,
                recentCombinations: recent,
                date: date,
                calendar: calendar
            ),
            sourceName: sourceName,
            allowsFindOne: profile.preferences.pieceMode == .mineAndOneIdea && !source.isSuitcase,
            layoutSeed: look.id.rawValue
        )
    }

    /// A model for Swap a piece, starting on `pieceID` (Swap it) or the first main piece.
    func swapModel(startingAt pieceID: LookPiece.ID? = nil) -> SwapModel? {
        swapSetup().map { SwapModel(setup: $0, pieceID: pieceID, makeLookID: makeLookID, now: now) }
    }

    /// Puts the pieces of a look changed in Swap into this saved look, keeping its ID, name,
    /// saved date and wear days. Returns the look before, for Undo.
    func applySwap(_ changed: Look) async throws(StoreError) -> Look {
        guard let services, let before = look else { throw .unavailable }
        var updated = before
        updated.pieces = changed.pieces
        try await services.looks.save(updated)
        replace(updated)
        return before
    }

    /// Undo for a swap or a removed piece: exactly the look before (LR-08.2).
    func restore(_ earlier: Look) async throws(StoreError) {
        guard let services else { throw .unavailable }
        try await services.looks.save(earlier)
        replace(earlier)
    }

    // MARK: Delete

    /// Delete look: takes it out of Saved Looks. Returns what Undo needs.
    func delete() async throws(StoreError) -> SavedLookRemoval {
        guard let services, let look else { throw .unavailable }
        let removal = SavedLookRemoval(look: look)
        try await removal.apply(in: services.looks)
        self.look = nil
        phase = .missing
        return removal
    }

    // MARK: Helpers

    private func replace(_ updated: Look) {
        look = updated
        if let index = looks.firstIndex(where: { $0.id == updated.id }) {
            looks[index] = updated
        }
    }

    private func reload() async {
        guard let services else { return }
        if let looks = try? await services.looks.looks(), let garments = try? await services.closet.garments() {
            show(looks: looks, garments: garments, suitcases: suitcases, profile: profile)
        }
    }
}

/// A look taken out of Saved Looks, and how to put it back.
///
/// A version of a styling result goes back to background history, unsaved and unnamed, as
/// unsaving on Your looks does (LR-06). A look she made herself has nowhere else to live, so it's
/// deleted. Undo saves the exact look again either way.
struct SavedLookRemoval: Hashable {
    let look: Look

    var name: String {
        look.name ?? SavedLooksText.unnamed(occasion: nil)
    }

    func apply(in store: any LookStore) async throws(StoreError) {
        if look.isMadeByHer {
            try await store.delete(look.id)
        } else {
            try await store.update(look.id) { look in
                look.isSaved = false
                look.name = nil
                look.savedAt = nil
            }
        }
    }

    func undo(in store: any LookStore) async throws(StoreError) {
        try await store.save(look)
    }
}
