import Foundation
import Models
import Observation

/// Add a piece and Edit (Phase 7b): the steps, the form, its checks, and the unsaved draft.
///
/// A new piece starts on "How would you like to add it?" (or straight on Describe in words),
/// then goes to the details form. An edit opens the details form filled in with the piece.
///
/// Every change is written to the `DraftStore` after a short pause (`draftSaveDelay`), and at
/// once when the app leaves the foreground, so closing the app mid-way never loses her work
/// (PRD §7.3: no reliance on a termination callback). Next time she opens the same form, or
/// Closet, she's offered "Continue where you left off?". A draft never touches her closet; only
/// Save does, and Save or Discard removes the draft.
@Observable
final class GarmentEditorModel {
    enum Phase: Equatable {
        case loading
        /// A draft from last time is waiting: Resume or Discard.
        case offeringResume
        case editing
        /// The piece being edited isn't in her closet any more.
        case gone
        /// A store failed. The screen shows its error state with Try again.
        case failed
    }

    /// The photo step's state.
    enum PhotoState: Equatable {
        case idle
        case loading
        /// The photo couldn't be read. Nothing changed.
        case failed
        /// The photo was read but couldn't be saved, for example on a full iPhone. Nothing changed.
        case notSaved
    }

    /// Describe in words: the suggestions' state.
    enum SuggestionState: Equatable {
        case idle
        case loading
        case loaded
        /// No suggestions came back. She can fill in the form herself.
        case failed
    }

    /// One suggestion and what she decided about it.
    struct SuggestionRow: Identifiable, Hashable {
        enum Decision: Hashable {
            case accepted
            case skipped
        }

        let id: Int
        let suggestion: GarmentSuggestion
        var decision: Decision?
        /// True once it has filled its field (on Continue).
        var isApplied = false
    }

    /// What Save did.
    enum Saved: Hashable {
        case added(Garment)
        case updated(Garment)

        var garment: Garment {
            switch self {
            case .added(let garment), .updated(let garment): garment
            }
        }
    }

    let target: GarmentDraft.Target
    /// The step the form opened on. Back from here closes the form instead.
    let firstStep: GarmentDraft.Step
    /// How long typing has to pause before the draft is written.
    let draftSaveDelay: Duration

    private(set) var phase: Phase = .loading
    private(set) var step: GarmentDraft.Step {
        didSet { if step != oldValue { changed() } }
    }
    /// The form's values. Bound to the fields.
    var details: GarmentDetails = .blank {
        didSet { if details != oldValue { changed() } }
    }
    /// The other name she's typing, before Add puts it with the others (Phase 21c). Not part of
    /// the draft until it's added; Save adds it first, so typed words aren't lost.
    var newOtherName = "" {
        didSet {
            guard newOtherName != oldValue else { return }
            if otherNameProblem != nil { otherNameProblem = nil }
            // Typing here waits for a pause before the draft is written, as typing in any other
            // field does. A draft written mid-word lost a letter of the name on the simulator.
            if !isRestoring { scheduleDraftSave() }
        }
    }
    /// Why the typed other name couldn't be added. Cleared as she types.
    private(set) var otherNameProblem: FieldProblem?
    /// Her own words, on Describe in words.
    var description = "" {
        didSet { if description != oldValue { changed() } }
    }
    /// What the form started from: blank, or the piece as it was.
    private(set) var base: GarmentDetails = .blank
    /// The piece's saved name, for an edit's title and messages.
    private(set) var savedName: String?
    /// A draft from last time, while Resume or Discard is offered.
    private(set) var pendingDraft: GarmentDraft?
    private(set) var suggestions: [SuggestionRow] = []
    private(set) var suggestionState: SuggestionState = .idle
    private(set) var photoState: PhotoState = .idle
    /// The photo choices to offer: the stand-in's three, or Take photo and Choose from Photos
    /// when real photos are on (Phase 22a).
    private(set) var photoSources: [PhotoSource] = PhotoSource.allCases
    /// True when the choices open the system camera and photo picker (Phase 22a). False for
    /// Stage A's stand-in, which the line under the choices explains.
    private(set) var usesSystemPicker = false
    /// The form's problems. Shown after the first Save, then kept up to date as she types.
    private(set) var problems = GarmentProblems()
    private(set) var showsProblems = false
    /// Counts the Saves that found problems, so the page can move VoiceOver to the first one.
    private(set) var problemCheckCount = 0
    /// Describe in words was too long.
    private(set) var descriptionProblem: FieldProblem?
    private(set) var isSaving = false
    /// The last Save didn't reach the store. Her words are still in the form.
    private(set) var saveFailed = false
    /// How many times a draft was written or removed, for tests of the save delay.
    private(set) var draftWrites = 0

    /// True once she went through Describe in words, so Back from the form returns there.
    private var cameFromWords: Bool
    private var drafts: (any DraftStore)?
    private var photos: (any PhotoIntake)?
    private var draftTask: Task<Void, Never>?
    /// Set while the model fills itself in, so loading isn't saved as her change.
    private var isRestoring = false
    @ObservationIgnored private var loads = LoadGeneration()
    private let resumesDraft: Bool
    private let now: () -> Date

    /// - Parameters:
    ///   - target: a new piece, or the piece to edit.
    ///   - firstStep: where a new piece starts (`.choose` or `.words`); an edit always starts on
    ///     the details form.
    ///   - resumesDraft: open straight into the waiting draft (Resume on Closet), without asking again.
    init(
        target: GarmentDraft.Target,
        firstStep: GarmentDraft.Step = .choose,
        resumesDraft: Bool = false,
        draftSaveDelay: Duration = .milliseconds(500),
        now: @escaping () -> Date = { .now }
    ) {
        self.target = target
        let first: GarmentDraft.Step = target == .newPiece ? firstStep : .details
        self.firstStep = first
        self.step = first
        self.cameFromWords = first == .words
        self.resumesDraft = resumesDraft
        self.draftSaveDelay = draftSaveDelay
        self.now = now
    }

    var isNewPiece: Bool { target == .newPiece }

    // MARK: Loading

    func load(from services: NookServices) async {
        drafts = services.drafts
        photos = services.photos
        photoSources = services.photos.sources
        usesSystemPicker = services.photos.usesSystemPicker
        let load = loads.begin()
        phase = .loading
        do {
            if case .garment(let id) = target {
                let garment = try await services.closet.garment(id)
                guard loads.isCurrent(load) else { return }
                guard garment.isInCloset else {
                    phase = .gone
                    return
                }
                restore {
                    base = GarmentDetails(garment)
                    details = base
                    savedName = garment.name
                }
            }
        } catch StoreError.notFound {
            if loads.isCurrent(load) { phase = .gone }
            return
        } catch {
            if loads.isCurrent(load) { phase = .failed }
            return
        }
        // A draft store that can't be read only means nothing to resume.
        let draft = try? await services.drafts.draft(for: target)
        guard loads.isCurrent(load) else { return }
        guard let draft, draft.hasChanges else {
            phase = .editing
            return
        }
        if resumesDraft {
            resume(draft)
        } else {
            pendingDraft = draft
            phase = .offeringResume
        }
    }

    /// Resume: the form as she left it, on the same step.
    func resume() {
        guard let pendingDraft else { return }
        resume(pendingDraft)
    }

    private func resume(_ draft: GarmentDraft) {
        restore {
            details = draft.details
            description = draft.description
            step = isNewPiece ? draft.step : .details
            cameFromWords = cameFromWords || !draft.description.isEmpty
        }
        pendingDraft = nil
        phase = .editing
    }

    /// Discard on "Continue where you left off?": the draft goes, and the form starts fresh.
    func discardPendingDraft() async {
        if let pendingDraft { await discardUnsavedPhoto(pendingDraft.details.photo, base: pendingDraft.base.photo) }
        pendingDraft = nil
        await removeDraft()
        phase = .editing
    }

    // MARK: Steps

    /// The step Back goes to, or `nil` when Back closes the form.
    var previousStep: GarmentDraft.Step? {
        guard isNewPiece else { return nil }
        switch step {
        case .choose: return nil
        case .words: return firstStep == .words ? nil : .choose
        case .details: return cameFromWords ? .words : (firstStep == .choose ? .choose : nil)
        }
    }

    func goBack() {
        guard let previousStep else { return }
        photoState = .idle
        step = previousStep
    }

    /// Describe in words, from the first step or the photo error.
    func describeInWords() {
        photoState = .idle
        cameFromWords = true
        step = .words
    }

    /// The photo step with Stage A's stand-in, which hands back a photo by itself. On the first
    /// step a photo moves on to the form; on the form it only changes the picture.
    func choosePhoto(from source: PhotoSource, using intake: any PhotoIntake) async {
        guard photoState != .loading else { return }
        photoState = .loading
        do {
            await use(try await intake.photo(from: source), using: intake)
        } catch {
            fail(error)
        }
    }

    /// The photo step with real photos (Phase 22a): the photo she picked or took is read, then
    /// `intake` keeps a copy without its metadata. What she picked is never kept as it came.
    func keepPhoto(_ picked: PickedPhoto, using intake: any PhotoIntake) async {
        guard photoState != .loading else { return }
        photoState = .loading
        let data: Data
        do {
            data = try await picked.load()
        } catch {
            photoState = .failed
            return
        }
        do {
            await use(try await intake.keep(data, from: picked.source), using: intake)
        } catch {
            fail(error)
        }
    }

    private func use(_ photo: PhotoReference, using intake: any PhotoIntake) async {
        let replaced = details.photo
        details.photo = photo
        photoState = .idle
        if step == .choose {
            cameFromWords = false
            step = .details
        }
        // A photo picked earlier in this form, and never saved, has nothing left pointing to it.
        if replaced != photo { await discardUnsavedPhoto(replaced, base: base.photo, using: intake) }
    }

    private func fail(_ error: PhotoIntakeError) {
        switch error {
        case .cancelled: photoState = .idle
        case .notSaved: photoState = .notSaved
        case .unreadable: photoState = .failed
        }
    }

    /// Removes a photo this form added and won't save. The piece's saved photo is never touched
    /// here; removing replaced or deleted pieces' photos is Phase 22b's.
    private func discardUnsavedPhoto(
        _ photo: PhotoReference, base: PhotoReference, using intake: (any PhotoIntake)? = nil
    ) async {
        guard photo != base, let intake = intake ?? photos else { return }
        await intake.discard(photo)
    }

    /// Try another photo, after one couldn't be read.
    func clearPhotoProblem() {
        photoState = .idle
    }

    // MARK: Describe in words

    func suggest(using reader: any GarmentDescriptionReader) async {
        let text: String
        do {
            text = try GarmentRules.description(description)
        } catch {
            descriptionProblem = error
            return
        }
        guard !text.isEmpty else {
            descriptionProblem = .empty
            return
        }
        descriptionProblem = nil
        suggestionState = .loading
        do {
            let found = try await reader.suggestions(for: text)
            suggestions = found.enumerated().map { SuggestionRow(id: $0.offset, suggestion: $0.element) }
            suggestionState = .loaded
        } catch {
            suggestions = []
            suggestionState = .failed
        }
    }

    /// Accept or Skip a suggestion. Choosing the same again undoes it.
    func decide(_ decision: SuggestionRow.Decision, for id: Int) {
        guard let index = suggestions.firstIndex(where: { $0.id == id }) else { return }
        suggestions[index].decision = suggestions[index].decision == decision ? nil : decision
    }

    /// Continue: the accepted suggestions fill their fields, then the form opens. Nothing she
    /// didn't accept is filled in, and a suggestion fills its field only once, so coming back
    /// and continuing again doesn't undo what she changed on the form.
    func continueFromWords() {
        if descriptionProblem == .empty { descriptionProblem = nil }
        var filled = details
        for index in suggestions.indices where suggestions[index].decision == .accepted && !suggestions[index].isApplied
        {
            suggestions[index].suggestion.apply(to: &filled)
            suggestions[index].isApplied = true
        }
        details = filled
        cameFromWords = true
        step = .details
    }

    // MARK: The form

    /// True when there's work to lose: changed details, or words she typed.
    var isDirty: Bool { currentDraft.hasChanges }

    /// Choose the kind. A type from another kind goes, since a cardigan can't be a shoe.
    func chooseCategory(_ category: GarmentCategory) {
        var changed = details
        changed.category = category
        if let subKind = changed.subKind, subKind.category != category { changed.subKind = nil }
        details = changed
    }

    /// Choose the type, or `nil` for none of these.
    func chooseSubKind(_ subKind: GarmentSubKind?) {
        details.subKind = subKind
    }

    /// The types she can pick for the chosen kind. Empty before a kind is chosen, and for kinds
    /// with no types (dresses).
    var subKindChoices: [GarmentSubKind] {
        details.category.map(GarmentSubKind.choices(for:)) ?? []
    }

    /// Add on Other names: the typed name joins the others, or the problem shows under the field.
    /// Returns whether it was added.
    @discardableResult
    func addOtherName() -> Bool {
        do {
            let name = try GarmentRules.newOtherName(newOtherName, adding: details)
            details.otherNames.append(name)
            newOtherName = ""
            otherNameProblem = nil
            return true
        } catch {
            otherNameProblem = error
            return false
        }
    }

    /// Removes one of the piece's other names.
    func removeOtherName(_ name: String) {
        details.otherNames.removeAll { $0 == name }
    }

    func toggleColor(_ color: ColorName) {
        if let index = details.colors.firstIndex(of: color) {
            details.colors.remove(at: index)
        } else {
            details.colors.append(color)
        }
    }

    func toggleSeason(_ season: Season) {
        details.seasons.formSymmetricDifference([season])
    }

    func toggleOccasion(_ occasion: Occasion) {
        details.occasions.formSymmetricDifference([occasion])
    }

    /// Save to closet, or Save changes. Checks the form first; with problems it shows them and
    /// saves nothing. Returns what was saved, or `nil`.
    func save(in closet: any ClosetStore) async -> Saved? {
        guard !isSaving else { return nil }
        showsProblems = true
        // A name typed under Other names but not added yet is added now, so it isn't lost. One
        // that can't be added stops Save, with its problem under the field.
        let pendingAdded = newOtherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || addOtherName()
        problems = GarmentRules.problems(in: details)
        if !pendingAdded, let otherNameProblem { problems.byField[.otherNames] = otherNameProblem }
        guard problems.isEmpty else {
            problemCheckCount += 1
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: Saved
            switch target {
            case .newPiece:
                let garment = try details.makeGarment(id: .random(), addedAt: now())
                try await closet.save(garment)
                saved = .added(garment)
            case .garment(let id):
                let checked = try GarmentRules.checked(details)
                saved = .updated(try await closet.update(id) { checked.apply(to: &$0) })
            }
            saveFailed = false
            draftTask?.cancel()
            await removeDraft()
            restore { base = details }
            return saved
        } catch {
            saveFailed = true
            return nil
        }
    }

    /// Cancel, after she confirmed: the work and its draft go.
    func discardChanges() async {
        draftTask?.cancel()
        await discardUnsavedPhoto(details.photo, base: base.photo)
        await removeDraft()
    }

    // MARK: The draft

    /// The draft as the form stands now.
    var currentDraft: GarmentDraft {
        GarmentDraft(
            target: target, step: step, details: details, base: base, description: description, savedAt: now())
    }

    /// Writes the draft now, for when the app leaves the foreground. Removes it when there's
    /// nothing to keep.
    func saveDraftNow() async {
        draftTask?.cancel()
        draftTask = nil
        await writeDraft()
    }

    /// Waits for a pending draft write, for tests.
    func settleDraft() async {
        await draftTask?.value
    }

    private func changed() {
        guard !isRestoring else { return }
        if showsProblems { problems = GarmentRules.problems(in: details) }
        if saveFailed { saveFailed = false }
        scheduleDraftSave()
    }

    private func scheduleDraftSave() {
        guard drafts != nil, phase == .editing else { return }
        draftTask?.cancel()
        let delay = draftSaveDelay
        draftTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.writeDraft()
        }
    }

    private func writeDraft() async {
        guard let drafts, phase == .editing else { return }
        let draft = currentDraft
        draftWrites += 1
        if draft.hasChanges {
            try? await drafts.save(draft)
        } else {
            try? await drafts.discard(target)
        }
    }

    private func removeDraft() async {
        guard let drafts else { return }
        draftWrites += 1
        try? await drafts.discard(target)
    }

    private func restore(_ change: () -> Void) {
        isRestoring = true
        change()
        isRestoring = false
    }
}
