import Foundation
import Models
import Observation

/// Make your own look (LR-08): building a look from scratch, piece by piece, with no styling,
/// no request and no connection (FR-32). It opens from a garment's Style with this, starting
/// with that piece, and from "+ Make your own" on Saved Looks.
///
/// Every change is written to the look draft store at once (LR-08.4, PRD §7.3), so a half-built
/// look is offered again after the app closes. The draft never touches Saved Looks; only Save
/// look does, and it names the look. Undo and Redo step through her changes.
@Observable
final class LookBuilderModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// Her closet couldn't be read. The screen shows its error state with Try again.
        case failed
    }

    /// The source Make your own look uses. Choosing a suitcase can come later.
    static let source: WardrobeSource = .mainCloset

    private(set) var phase: Phase = .loading
    /// Her pieces in the look, in the order she added them. One of each kind.
    private(set) var pieceIDs: [Garment.ID] = []
    /// What she typed in Name this look.
    var name = "" {
        didSet {
            guard name != oldValue, !isSettingName else { return }
            changed()
        }
    }
    /// A half-built look from before, offered as "Continue your look?" until she chooses.
    private(set) var offeredDraft: LookDraft?
    /// The saved look, once she's saved. Saving again updates it (PRD §7.3).
    private(set) var savedLook: Look?
    /// True when something changed since the last save.
    private(set) var hasUnsavedChanges = false
    /// True when the last draft write failed, so the screen can say the draft isn't kept.
    private(set) var draftSaveFailed = false

    /// Every garment she has, by ID.
    private(set) var garments: [Garment.ID: Garment] = [:]
    private(set) var suitcases: [Suitcase] = []
    private(set) var tracksLaundry = false
    /// When the screen loaded, for eligibility and "Last worn".
    private(set) var loadedAt: Date = .now

    let startingPieceID: Garment.ID?
    private var history = EditHistory<[Garment.ID]>()
    private var services: NookServices?
    private var draftWriting: Task<Void, Never>?
    /// True while the model sets the name itself (resuming, or naming on save), which isn't a
    /// change of hers.
    private var isSettingName = false
    private let now: () -> Date
    private let makeLookID: () -> Look.ID

    init(
        startingPieceID: Garment.ID? = nil,
        now: @escaping () -> Date = { .now },
        makeLookID: @escaping () -> Look.ID = { .random() }
    ) {
        self.startingPieceID = startingPieceID
        self.now = now
        self.makeLookID = makeLookID
    }

    // MARK: Loading

    /// Reads her closet and any draft. A draft with work in it is offered; otherwise the look
    /// starts with the starting piece, if it can be worn.
    func load(from services: NookServices?) async {
        self.services = services
        guard let services else {
            phase = .loaded
            return
        }
        if garments.isEmpty { phase = .loading }
        do {
            async let garmentList = services.closet.garments()
            async let suitcaseList = services.suitcases.suitcases()
            async let profile = services.profile.profile()
            let all = try await garmentList
            suitcases = try await suitcaseList
            tracksLaundry = try await profile.preferences.tracksLaundry
            garments = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            phase = .failed
            return
        }
        loadedAt = now()
        let wasLoaded = phase == .loaded
        phase = .loaded
        // Coming back to the screen keeps what's on it.
        guard !wasLoaded, pieceIDs.isEmpty, savedLook == nil, offeredDraft == nil else { return }
        let draft = (try? await services.lookDrafts.draft()) ?? nil
        if let draft, draft.hasChanges {
            offeredDraft = draft
        }
        if let start = startingPieceID, let garment = garments[start], isUsable(garment) {
            pieceIDs = [start]
        }
    }

    /// Continue your look: picks up the draft where she left it.
    func resumeDraft() {
        guard let draft = offeredDraft else { return }
        offeredDraft = nil
        history.clear()
        pieceIDs = draft.garmentIDs.filter { id in garments[id].map(isUsable) ?? false }
        setName(draft.name)
        hasUnsavedChanges = true
        writeDraft()
    }

    /// Start over: throws the old draft away and keeps what's on the screen.
    func discardOfferedDraft() {
        guard offeredDraft != nil else { return }
        offeredDraft = nil
        if pieceIDs != (startingPieceID.map { [$0] } ?? []) || !name.isEmpty {
            writeDraft()
        } else {
            let drafts = services?.lookDrafts
            let previous = draftWriting
            draftWriting = Task {
                await previous?.value
                try? await drafts?.discard()
            }
        }
    }

    // MARK: Pieces

    /// The look's garments in body order (layer, top, dress, bottom, shoes, bag, accessory).
    var pieces: [Garment] {
        pieceIDs.compactMap { garments[$0] }.sorted { $0.category < $1.category }
    }

    /// Adds a piece. A piece of a kind the look already has takes its place: one of each kind.
    func add(_ id: Garment.ID) {
        guard let garment = garments[id], !pieceIDs.contains(id) else { return }
        var next = pieceIDs.filter { garments[$0]?.category != garment.category }
        next.append(id)
        apply(next)
    }

    func remove(_ id: Garment.ID) {
        guard pieceIDs.contains(id) else { return }
        apply(pieceIDs.filter { $0 != id })
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func undo() {
        guard let earlier = history.undo(from: pieceIDs) else { return }
        pieceIDs = earlier
        changed()
    }

    func redo() {
        guard let later = history.redo(from: pieceIDs) else { return }
        pieceIDs = later
        changed()
    }

    private func apply(_ next: [Garment.ID]) {
        guard next != pieceIDs else { return }
        history.record(pieceIDs)
        pieceIDs = next
        changed()
    }

    // MARK: Checks

    /// What stops the look from being saved, in the order the screen says them.
    var problems: [LookProblem] {
        LookRules.problems(building: pieces, members: nil, tracksLaundry: tracksLaundry, on: loadedAt)
    }

    /// The typed name's problem, if it has one. An empty name is fine: saving names the look
    /// from its colours.
    var nameProblem: NameProblem? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            _ = try NameRules.lookName(name)
            return nil
        } catch {
            return error
        }
    }

    var canSave: Bool { phase == .loaded && problems.isEmpty && nameProblem == nil && hasUnsavedChanges }

    /// The look as it stands, for the bundle.
    var look: Look {
        let id = savedLook?.id ?? Look.ID("look-builder")
        return Look(
            id: id,
            pieces: pieces.map { LookPiece(id: LookPiece.ID("\(id)-\($0.id)"), content: .garment($0.id)) },
            name: name.isEmpty ? nil : name,
            source: Self.source,
            createdAt: loadedAt
        )
    }

    /// The pieces Add a piece offers: everything she can wear from the closet now, by kind and
    /// then by name.
    func pickerScope() -> PieceScope {
        let usable = garments.values.filter(isUsable).sorted { lhs, rhs in
            if lhs.category != rhs.category { return lhs.category < rhs.category }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id < rhs.id
        }
        var notes: [Garment.ID: String] = [:]
        for id in pieceIDs { notes[id] = SwapText.inTheLook }
        return PieceScope(garmentIDs: usable.map(\.id), notes: notes)
    }

    private func isUsable(_ garment: Garment) -> Bool {
        Eligibility.isEligible(garment, members: nil, tracksLaundry: tracksLaundry, on: loadedAt)
    }

    // MARK: Saving

    /// Saves the look to Saved Looks with its name, and drops the draft. Saving again after more
    /// changes updates the same look.
    ///
    /// - Parameter fallbackName: the name to use when she didn't type one.
    @discardableResult
    func save(fallbackName: String) async throws(StoreError) -> Look {
        guard let services else { throw .unavailable }
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = savedLook?.id ?? makeLookID()
        let look = Look(
            id: id,
            pieces: pieces.map { LookPiece(id: LookPiece.ID("\(id)-\($0.id)"), content: .garment($0.id)) },
            name: typed.isEmpty ? fallbackName : typed,
            source: Self.source,
            isSaved: true,
            savedAt: savedLook?.savedAt ?? now(),
            wornOn: savedLook?.wornOn ?? [],
            createdAt: savedLook?.createdAt ?? now()
        )
        try await services.looks.save(look)
        savedLook = look
        if typed.isEmpty { setName(look.name ?? "") }
        hasUnsavedChanges = false
        let drafts = services.lookDrafts
        let previous = draftWriting
        draftWriting = Task {
            await previous?.value
            try? await drafts.discard()
        }
        return look
    }

    // MARK: Draft

    private func setName(_ value: String) {
        isSettingName = true
        name = value
        isSettingName = false
    }

    /// Waits for draft writes, for tests.
    func settle() async {
        await draftWriting?.value
    }

    private func changed() {
        hasUnsavedChanges = true
        // While an older draft is offered, it's kept until she chooses.
        guard offeredDraft == nil else { return }
        writeDraft()
    }

    private func writeDraft() {
        guard let drafts = services?.lookDrafts, phase == .loaded else { return }
        let draft = LookDraft(
            name: name, source: Self.source, garmentIDs: pieceIDs, startingPieceID: startingPieceID,
            savedAt: now())
        let previous = draftWriting
        draftWriting = Task { [weak self] in
            await previous?.value
            do {
                try await drafts.save(draft)
                self?.draftSaveFailed = false
            } catch {
                self?.draftSaveFailed = true
            }
        }
    }
}
