import Foundation
import Models
import Observation

/// Your looks, the Style Me results (LR-05a, LR-05b, LR-06, RD-06).
///
/// One request gives one outfit in up to three versions (Simple, Dressed up, Something new).
/// The Today tab shows the selected version; the Saved tab lists the looks she saved for the same
/// source and occasion, and opening it sends nothing (LR-06.1). Try a different outfit sends
/// exactly one more request and replaces all three versions (LR-05a.4). Every result is kept in
/// the look store as background history, unsaved (LR-06).
///
/// Only `start`, `retry` and `tryDifferentOutfit` call the stylist. Leaving the screen cancels a
/// request that's still running, and its answer is never shown.
///
/// Swap a piece changes a version by hand (Phase 11, LR-07, LR-08): the changed look takes the
/// version's place on Today, marked "Swapped", and Undo steps back through the changes to the
/// stylist's look exactly. Changes stay on this screen until she saves the look; a new result
/// starts clean.
@Observable
final class YourLooksModel {
    enum Tab: String, Hashable, CaseIterable {
        case today
        case saved
    }

    /// Why styling didn't give a result. None of these claims the closet is too small (LR-05a).
    enum Failure: Hashable {
        /// No connection.
        case offline
        /// The stylist didn't finish, or its answer didn't pass `ResultCheck`.
        case notCompleted
        /// She left while it was styling, so it stopped.
        case stopped
        /// Her closet or looks couldn't be read, so nothing was sent.
        case closetUnavailable
        /// The suitcase or starting piece changed since she asked (`StylingContextError`).
        case requestChanged
    }

    enum Status: Equatable {
        /// Nothing sent yet. The screen starts styling when it first appears.
        case notStarted
        case styling(StylingStep)
        /// A result is on screen: all three versions, or fewer with `missing` saying why.
        case showing
        /// No valid outfit in this source (InsufficientWardrobe).
        case insufficient(InsufficientWardrobe)
        /// No result to show. A failure while an earlier result stays on screen is `problem`.
        case failed(Failure)
    }

    /// Where styling has got to, for the progress steps.
    enum StylingStep: Int, Equatable, Comparable {
        /// Reading the closet and building the request's context, on the phone.
        case checking
        /// Waiting for the stylist.
        case choosing

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private(set) var status: Status = .notStarted
    /// The request on screen. Try a different outfit replaces it with a copy with a new ID.
    private(set) var request: StyleRequest
    private(set) var result: StyleResult?
    /// Versions the stylist couldn't make, with why (a partial result).
    private(set) var missing: [MissingVersion] = []
    /// A failure while the earlier result stays on screen, such as Try a different outfit offline.
    private(set) var problem: Failure?
    var tab: Tab = .today
    /// The version on the Today tab. Switching sends nothing (LR-05a.2).
    var version: LookVersion = .simple

    /// Everything in her closet, by ID, for drawing and naming pieces.
    private(set) var garments: [Garment.ID: Garment] = [:]
    /// Every look in the store, newest first: saved ones and background history.
    private(set) var looks: [Look] = []
    /// The suitcase's name when the source is a suitcase.
    private(set) var suitcaseName: String?
    /// Her suitcases, for Swap's See all filter.
    private(set) var suitcases: [Suitcase] = []
    /// Her usual fit, for ranking swaps when the request has no comfort for today.
    private(set) var usualFit: Comfort?
    /// Versions she changed with Swap a piece, as they are now (Phase 11).
    private(set) var edits: [LookVersion: Look] = [:]
    /// Each changed version's earlier looks, for Undo (LR-08.2).
    private var histories: [LookVersion: EditHistory<Look>] = [:]
    /// Pieces the stylist could use for this request, for the progress step.
    private(set) var usablePieces = 0
    /// How many times the stylist was asked, for tests and the checkpoint.
    private(set) var requestsSent = 0
    /// True when the looks couldn't be read, so the Saved tab shows its error state.
    private(set) var looksUnavailable = false

    /// Main-piece combinations already shown for this request.
    private var shown: Set<Set<Garment.ID>> = []
    private var services: NookServices?
    private var styling: Task<Void, Never>?
    /// Bumped by every new run and by cancelling, so a stale answer is never shown.
    private var run = 0
    private let now: () -> Date
    private let calendar: Calendar
    private let makeID: () -> StyleRequest.ID
    private let makeLookID: () -> Look.ID

    init(
        request: StyleRequest,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current,
        makeID: @escaping () -> StyleRequest.ID = { .random() },
        makeLookID: @escaping () -> Look.ID = { .random() }
    ) {
        self.request = request
        self.now = now
        self.calendar = calendar
        self.makeID = makeID
        self.makeLookID = makeLookID
    }

    // MARK: Styling

    /// Sends the request the first time the screen appears. Coming back to the screen never
    /// sends it again on its own.
    func start(with services: NookServices?) {
        guard status == .notStarted else { return }
        self.services = services
        style()
    }

    /// Tries the same request again after a failure. Sends one request.
    func retry() {
        guard !isStyling else { return }
        style()
    }

    /// Asks for a new base outfit (LR-05a.4): one more request with the same choices. The
    /// versions on screen stay until the new ones arrive, and come back if it fails.
    func tryDifferentOutfit() {
        guard !isStyling, let result else { return }
        let categories = garments.mapValues(\.category)
        for look in result.versions {
            let main = WearRules.mainPieces(of: look, categories: categories)
            if !main.isEmpty { shown.insert(main) }
        }
        request = request.again(id: makeID(), createdAt: now())
        style()
    }

    /// Stops a request that's still running: Cancel, or leaving the screen. Its answer, if it
    /// comes, is dropped. With a result on screen she's back on it; without one, it's stopped.
    func cancel() {
        guard isStyling else { return }
        run += 1
        styling?.cancel()
        styling = nil
        status = result == nil ? .failed(.stopped) : .showing
    }

    /// Waits for the running request, for tests.
    func settle() async {
        await styling?.value
    }

    var isStyling: Bool {
        if case .styling = status { true } else { false }
    }

    private func style() {
        run += 1
        let thisRun = run
        problem = nil
        status = .styling(.checking)
        requestsSent += 1
        let request = request
        styling = Task { [weak self] in
            await self?.perform(request, run: thisRun)
        }
    }

    private func perform(_ request: StyleRequest, run thisRun: Int) async {
        guard let services else { return finish(.closetUnavailable, run: thisRun) }
        let context: StylingContext
        do {
            async let garmentList = services.closet.garments()
            async let suitcaseList = services.suitcases.suitcases()
            async let lookList = services.looks.looks()
            async let profile = services.profile.profile()
            let (garments, suitcases, looks) = try await (garmentList, suitcaseList, lookList)
            let usualFit = try await profile.usualFit
            guard thisRun == run else { return }
            self.usualFit = usualFit
            show(garments: garments, suitcases: suitcases, looks: looks)
            context = try StylingContext.make(
                request: request, garments: garments, suitcases: suitcases, looks: looks, usualFit: usualFit,
                shown: shown, now: now(), calendar: calendar)
        } catch is StylingContextError {
            return finish(.requestChanged, run: thisRun)
        } catch {
            return finish(.closetUnavailable, run: thisRun)
        }
        usablePieces = context.eligibleGarments.count
        status = .styling(.choosing)

        let outcome: StyleOutcome
        do {
            outcome = try await services.stylist.style(context)
        } catch {
            return finish(Self.failure(for: error), run: thisRun)
        }
        guard thisRun == run else { return }
        if let result = outcome.result, !ResultCheck.problems(in: result, for: context).isEmpty {
            return finish(.notCompleted, run: thisRun)
        }
        await keep(outcome, services: services)
        guard thisRun == run else { return }
        show(outcome)
        styling = nil
    }

    /// Keeps the versions as unsaved background history (LR-06) and marks a suitcase as used
    /// (RD-09.2). Neither failing stops the result from showing.
    private func keep(_ outcome: StyleOutcome, services: NookServices) async {
        for look in outcome.result?.versions ?? [] {
            try? await services.looks.save(look)
        }
        if let suitcaseID = request.source.suitcaseID {
            try? await services.suitcases.markUsed(suitcaseID, at: now())
        }
        await reloadLooks()
    }

    private func show(_ outcome: StyleOutcome) {
        switch outcome {
        case .complete(let result):
            self.result = result
            missing = []
            status = .showing
        case .partial(let result, let missing):
            self.result = result
            self.missing = missing
            status = .showing
        case .insufficient(let wardrobe):
            result = nil
            missing = []
            status = .insufficient(wardrobe)
        }
        version = .simple
        tab = .today
        edits = [:]
        histories = [:]
    }

    /// Ends a run that failed. With a result already on screen, it stays and the failure becomes
    /// a note above it.
    private func finish(_ failure: Failure, run thisRun: Int) {
        guard thisRun == run else { return }
        styling = nil
        if result != nil {
            problem = failure
            status = .showing
        } else {
            status = .failed(failure)
        }
    }

    private static func failure(for error: StylistError) -> Failure {
        switch error {
        case .offline: .offline
        case .cancelled: .stopped
        case .notCompleted, .timedOut: .notCompleted
        case .invalidRequest: .requestChanged
        }
    }

    private func show(garments: [Garment], suitcases: [Suitcase], looks: [Look]) {
        self.garments = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.looks = looks
        self.suitcases = suitcases
        looksUnavailable = false
        suitcaseName = request.source.suitcaseID.flatMap { id in suitcases.first { $0.id == id }?.name }
    }

    // MARK: Saved tab

    /// Looks she saved for this source and occasion, newest first (LR-06.1). Unsaved earlier
    /// results are never listed (LR-06.4).
    var savedLooks: [Look] {
        looks.filter { $0.isSaved && $0.source == request.source && $0.occasion == request.occasion }
    }

    /// Reads the looks again, for the Saved tab. Sends nothing.
    func reloadLooks() async {
        guard let services else { return }
        do {
            looks = try await services.looks.looks()
            looksUnavailable = false
        } catch {
            looksUnavailable = true
        }
    }

    // MARK: Today tab

    /// The versions on screen, in switch order.
    var versions: [LookVersion] {
        result?.versions.compactMap(\.version) ?? []
    }

    /// The selected version's look as it is now (changed by Swap, or as the stylist made it),
    /// or Simple if the selected one isn't in this result.
    var currentLook: Look? {
        guard let result else { return nil }
        let shown = result.look(for: version) != nil ? version : .simple
        return edits[shown] ?? result.look(for: shown)
    }

    /// The version actually shown.
    var shownVersion: LookVersion {
        currentLook?.version ?? .simple
    }

    // MARK: Swap a piece

    /// The stylist's look for the version on screen, before any swap.
    var originalLook: Look? {
        result?.look(for: shownVersion) ?? result?.simple
    }

    /// True when the version on screen has a change Undo can take back.
    var canUndoChange: Bool {
        histories[shownVersion]?.canUndo ?? false
    }

    /// What Swap a piece needs for the look on screen. Gathered from what this screen already
    /// loaded, so Swap reads nothing and sends nothing (LR-07.1).
    func swapSetup(sourceName: String) -> SwapSetup? {
        guard let look = currentLook else { return nil }
        let members = request.source.suitcaseID.flatMap { id in suitcases.first { $0.id == id }?.garmentIDs }
        let recent = WearRules.recentCombinations(
            in: looks, categories: garments.mapValues(\.category), window: request.preferences.repeatWindow,
            now: now(), calendar: calendar)
        return SwapSetup(
            look: look,
            simple: result?.simple,
            garments: garments,
            suitcases: suitcases,
            situation: SwapSituation(
                source: request.source,
                members: members,
                occasion: request.occasion,
                weather: request.weatherToUse,
                fit: (request.comfort ?? usualFit)?.matchingFit,
                tracksLaundry: request.preferences.tracksLaundry,
                recentCombinations: recent,
                date: now(),
                calendar: calendar
            ),
            sourceName: sourceName,
            allowsFindOne: request.allowsNewPieceIdea,
            layoutSeed: originalLook?.id.rawValue
        )
    }

    /// A model for Swap a piece on the look on screen, with this screen's clock and IDs.
    func swapModel(sourceName: String) -> SwapModel? {
        swapSetup(sourceName: sourceName).map { SwapModel(setup: $0, makeLookID: makeLookID, now: now) }
    }

    /// Puts a look changed in Swap in its version's place, keeping the one before for Undo.
    func apply(_ changed: Look) {
        let version = changed.version ?? shownVersion
        guard let before = edits[version] ?? result?.look(for: version) else { return }
        histories[version, default: EditHistory()].record(before)
        edits[version] = changed
        self.version = version
    }

    /// Undo for the latest swap or removal on the version on screen. Gives back exactly the look
    /// before it (LR-08.2). Returns false when there was nothing to undo.
    @discardableResult
    func undoChange() -> Bool {
        let version = shownVersion
        guard let current = currentLook, let earlier = histories[version]?.undo(from: current) else { return false }
        edits[version] = earlier.id == result?.look(for: version)?.id ? nil : earlier
        return true
    }

    func isSaved(_ look: Look) -> Bool {
        looks.first { $0.id == look.id }?.isSaved ?? false
    }

    // MARK: Saving

    /// What Save look did, for the toast and its Undo.
    enum SaveChange: Equatable {
        case saved(Look.ID)
        case unsaved(Look.ID)
    }

    /// Saves the look on screen, or takes it out of Saved Looks if it's saved. Saving names it
    /// (LR-08) and never makes an idea piece owned (LR-05b.3).
    func toggleSave(_ look: Look, name: String) async throws(StoreError) -> SaveChange {
        if isSaved(look) {
            try await setSaved(false, look: look, name: nil)
            return .unsaved(look.id)
        }
        try await setSaved(true, look: look, name: name)
        return .saved(look.id)
    }

    /// Undo for a save or unsave.
    func undo(_ change: SaveChange, name: String) async throws(StoreError) {
        let id: Look.ID
        let saved: Bool
        switch change {
        case .saved(let lookID): (id, saved) = (lookID, false)
        case .unsaved(let lookID): (id, saved) = (lookID, true)
        }
        guard let look = looks.first(where: { $0.id == id }) ?? result?.versions.first(where: { $0.id == id })
        else { return }
        try await setSaved(saved, look: look, name: saved ? name : nil)
    }

    private func setSaved(_ saved: Bool, look: Look, name: String?) async throws(StoreError) {
        guard let services else { throw .unavailable }
        var updated = looks.first { $0.id == look.id } ?? look
        updated.isSaved = saved
        updated.name = saved ? (updated.name ?? name) : nil
        updated.savedAt = saved ? (updated.savedAt ?? now()) : nil
        try await services.looks.save(updated)
        if let index = looks.firstIndex(where: { $0.id == updated.id }) {
            looks[index] = updated
        } else {
            looks.insert(updated, at: 0)
        }
    }
}
