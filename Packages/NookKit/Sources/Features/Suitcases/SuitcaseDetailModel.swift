import Foundation
import Models
import Observation

/// One suitcase (`suitcase.html`, PRD §7.7, FR-66): its packed pieces, whether Style Me uses it,
/// and the changes she can make: pack and unpack pieces, use it for Style Me, rename it and change
/// its picture, archive it and delete it.
///
/// Only pieces in her closet show. A piece she no longer has, or one in Recently deleted, keeps
/// its link in the data, so Undo brings it back as it was, but it never shows here or counts
/// (LR-16.1). Every change goes through the stores, so Stage B's real stores get the same calls.
@Observable
final class SuitcaseDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The suitcase isn't there any more: deleted elsewhere.
        case gone
        /// A store failed. The screen shows its error state with Try again.
        case failed
    }

    let suitcaseID: Suitcase.ID
    private(set) var phase: Phase = .loading
    private(set) var suitcase: Suitcase?
    /// The packed pieces in her closet, newest first, as the grid shows them.
    private(set) var items: [ClosetItem] = []
    /// The source Style Me uses now.
    private(set) var source: WardrobeSource = .mainCloset
    /// The source's name, for "Now it uses Main closet".
    private(set) var sourceName = SuitcasesText.mainCloset
    /// Every piece in her closet, for the packing sheet.
    private(set) var closetGarments: [Garment] = []
    /// Every suitcase, for names on the packing sheet and checking a new name.
    private(set) var allSuitcases: [Suitcase] = []
    private(set) var profile = Profile()
    /// When it loaded, for "Used 3 days ago".
    private(set) var loadedAt: Date = .now
    /// True while a change is being saved, so a second tap does nothing.
    private(set) var isSaving = false

    init(suitcaseID: Suitcase.ID) {
        self.suitcaseID = suitcaseID
    }

    // MARK: Loading

    func load(from services: NookServices?, now: Date = .now) async {
        guard let services else {
            phase = .gone
            return
        }
        if suitcase == nil { phase = .loading }
        do {
            async let suitcaseList = services.suitcases.suitcases()
            async let garmentList = services.closet.garments()
            async let profile = services.profile.profile()
            show(
                suitcases: try await suitcaseList, garments: try await garmentList, profile: try await profile,
                now: now)
        } catch {
            phase = .failed
        }
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(suitcases: [Suitcase], garments: [Garment], profile: Profile, now: Date) {
        loadedAt = now
        self.profile = profile
        allSuitcases = suitcases
        guard let suitcase = suitcases.first(where: { $0.id == suitcaseID }) else {
            self.suitcase = nil
            items = []
            phase = .gone
            return
        }
        self.suitcase = suitcase
        closetGarments = garments.filter(\.isInCloset)
        source = SourceChoice.shown(profile.remembered.source, among: suitcases)
        sourceName =
            source.suitcaseID.flatMap { id in suitcases.first { $0.id == id }?.name } ?? SuitcasesText.mainCloset
        let tracksLaundry = profile.preferences.tracksLaundry
        // The other suitcases' names, for "Also in Weekend" (VoiceOver reads them on each piece).
        let others = suitcases.filter { !$0.isArchived && $0.id != suitcaseID }
        items = SourceChoice.pieces(in: .suitcase(suitcaseID), garments: garments, suitcases: suitcases).map {
            garment in
            ClosetItem(
                garment, suitcaseNames: others.filter { $0.contains(garment.id) }.map(\.name),
                tracksLaundry: tracksLaundry)
        }
        phase = .loaded
    }

    // MARK: What the screen shows

    var isSource: Bool { source == .suitcase(suitcaseID) }
    var pieceCount: Int { items.count }
    var isArchived: Bool { suitcase?.isArchived ?? false }

    /// A model for the packing sheet: Closet's search, filters and grid over every piece in her
    /// closet, read from what's already loaded.
    func packingList() -> ClosetModel {
        let list = ClosetModel(scope: PieceScope(garmentIDs: closetGarments.map(\.id)))
        refresh(list)
        return list
    }

    /// Fills the packing sheet's list from what's loaded now. Laundry doesn't matter for
    /// packing, so the Dirty badge stays off and never sits on a tick.
    func refresh(_ list: ClosetModel) {
        var packingProfile = profile
        packingProfile.preferences.tracksLaundry = false
        list.show(closetGarments, suitcases: allSuitcases, profile: packingProfile, now: loadedAt)
    }

    func isPacked(_ id: Garment.ID) -> Bool {
        suitcase?.contains(id) ?? false
    }

    func nameProblem(_ text: String) -> NameProblem? {
        do {
            _ = try NameRules.suitcaseName(text, among: allSuitcases, renaming: suitcaseID)
            return nil
        } catch {
            return error
        }
    }

    // MARK: Packing

    /// Packs or unpacks one piece on the packing sheet. Returns true when it's now packed.
    @discardableResult
    func togglePacked(_ id: Garment.ID, in services: NookServices?, now: Date = .now) async throws(StoreError) -> Bool {
        guard let services else { throw .unavailable }
        let packing = !isPacked(id)
        if packing {
            try await services.suitcases.add([id], to: suitcaseID)
        } else {
            try await services.suitcases.remove([id], from: suitcaseID)
        }
        await load(from: services, now: now)
        return packing
    }

    /// Takes a piece out of this suitcase only. It stays in her closet and any other suitcase.
    func remove(_ id: Garment.ID, in services: NookServices?, now: Date = .now) async throws(StoreError) {
        guard let services, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        try await services.suitcases.remove([id], from: suitcaseID)
        await load(from: services, now: now)
    }

    /// Undo after Remove: packs it again.
    func putBack(_ id: Garment.ID, in services: NookServices?, now: Date = .now) async throws(StoreError) {
        guard let services else { return }
        try await services.suitcases.add([id], to: suitcaseID)
        await load(from: services, now: now)
    }

    // MARK: Source

    /// Use for Style Me (FR-67): remembered for next time and marked as used, so it's a
    /// favourite (RD-09.2). Returns the source it replaced, for Undo.
    func useForStyleMe(in services: NookServices?, now: Date = .now) async throws(StoreError) -> WardrobeSource? {
        try await setSource(.suitcase(suitcaseID), in: services, now: now)
    }

    /// Sets the source Style Me uses. Returns the one it replaced.
    @discardableResult
    func setSource(_ newSource: WardrobeSource, in services: NookServices?, now: Date = .now) async throws(StoreError)
        -> WardrobeSource?
    {
        guard let services, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        let previous = source
        try await services.profile.update { $0.remembered.source = newSource }
        if let id = newSource.suitcaseID {
            try await services.suitcases.markUsed(id, at: now)
        }
        await load(from: services, now: now)
        return previous
    }

    // MARK: Name, picture, archive, delete

    func edit(name: String, icon: SuitcaseIcon, in services: NookServices?, now: Date = .now) async throws(StoreError) {
        guard let services else { throw .unavailable }
        try await services.suitcases.update(suitcaseID) { suitcase in
            suitcase.name = name
            suitcase.icon = icon
        }
        await load(from: services, now: now)
    }

    /// Archive or bring back (PRD §7.7). Archiving keeps its pieces and hides it from the source
    /// choices; if it was the source, Style Me goes back to the main closet. Returns how to undo it.
    func setArchived(_ archived: Bool, in services: NookServices?, now: Date = .now) async throws(StoreError)
        -> SuitcaseChange?
    {
        guard let services, let suitcase, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        let wasSource = isSource
        try await services.suitcases.update(suitcaseID) { $0.isArchived = archived }
        if archived && wasSource {
            try await services.profile.update { $0.remembered.source = .mainCloset }
        }
        await load(from: services, now: now)
        return SuitcaseChange(suitcase: suitcase, kind: archived ? .archived : .broughtBack, wasSource: wasSource)
    }

    /// Delete suitcase (PRD §7.7): its links go, its pieces, saved looks and pictures stay. If it
    /// was the source, Style Me goes back to the main closet with a toast that says so. Undo puts
    /// back the same suitcase.
    func delete(in services: NookServices?) async throws(StoreError) -> SuitcaseChange? {
        guard let services, let suitcase, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        let wasSource = profile.remembered.source == .suitcase(suitcaseID)
        try await services.suitcases.delete(suitcaseID)
        if wasSource {
            try await services.profile.update { $0.remembered.source = .mainCloset }
        }
        return SuitcaseChange(suitcase: suitcase, kind: .deleted, wasSource: wasSource)
    }
}

/// A suitcase she just archived, brought back or deleted, with how to undo it.
nonisolated struct SuitcaseChange: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case archived
        case broughtBack
        case deleted
    }

    /// The suitcase as it was before.
    let suitcase: Suitcase
    let kind: Kind
    /// True when it was Style Me's source, which then went back to the main closet.
    let wasSource: Bool

    /// What the toast says.
    var message: String {
        switch kind {
        case .archived:
            wasSource
                ? String(
                    localized: "\(suitcase.name) is archived. Style Me now uses Main closet.", bundle: .module,
                    comment: "Toast after archiving the source suitcase")
                : String(
                    localized: "\(suitcase.name) is archived.", bundle: .module,
                    comment: "Toast after archiving a suitcase")
        case .broughtBack:
            String(
                localized: "\(suitcase.name) is back.", bundle: .module,
                comment: "Toast after bringing back an archived suitcase")
        case .deleted:
            wasSource
                ? String(
                    localized: "\(suitcase.name) is deleted. Style Me now uses Main closet.", bundle: .module,
                    comment: "Toast after deleting the source suitcase; its pieces stay in the closet")
                : String(
                    localized: "\(suitcase.name) is deleted. Its pieces are still in your closet.", bundle: .module,
                    comment: "Toast after deleting a suitcase")
        }
    }

    /// Undo: the same suitcase as it was, and the source it was, if it was the source.
    func undo(in services: NookServices) async throws(StoreError) {
        switch kind {
        case .archived, .broughtBack:
            let archived = suitcase.isArchived
            try await services.suitcases.update(suitcase.id) { $0.isArchived = archived }
        case .deleted:
            try await services.suitcases.restore(suitcase)
        }
        if wasSource {
            let id = suitcase.id
            try await services.profile.update { $0.remembered.source = .suitcase(id) }
        }
    }
}
