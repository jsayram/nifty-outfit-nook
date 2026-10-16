import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Fixture services on the fixed test clock, with an optional draft waiting.
@MainActor
func editorServices(
    _ set: FixtureSet = .demo,
    behavior: FixtureBehavior = .normal,
    laundry: FixtureLaundryState? = nil,
    draft: FixtureDraftState? = nil
) -> NookServices {
    FixtureServices.make(
        set: set, behavior: behavior, laundry: laundry, draft: draft, now: ClosetTestTime.now,
        calendar: ClosetTestTime.calendar)
}

/// An editor model loaded the way the screen loads it. Drafts are written at once unless a
/// delay is given, so tests can read the store straight after a change.
@MainActor
func loadedEditor(
    _ target: GarmentDraft.Target = .newPiece,
    firstStep: GarmentDraft.Step = .choose,
    resumesDraft: Bool = false,
    draftSaveDelay: Duration = .zero,
    services: NookServices
) async -> GarmentEditorModel {
    let model = GarmentEditorModel(
        target: target, firstStep: firstStep, resumesDraft: resumesDraft, draftSaveDelay: draftSaveDelay,
        now: { ClosetTestTime.now })
    await model.load(from: services)
    return model
}

/// Add a piece: steps, the form's checks and Save (Phase 7b).
@MainActor
struct AddPieceModelTests {
    @Test func aNewPieceStartsBlankOnTheChoices() async {
        let model = await loadedEditor(services: editorServices())
        #expect(model.phase == .editing)
        #expect(model.step == .choose)
        #expect(model.details == .blank)
        #expect(!model.isDirty)
        #expect(model.previousStep == nil)
        #expect(model.isNewPiece)
    }

    @Test func describeInWordsCanBeTheFirstStep() async {
        let model = await loadedEditor(firstStep: .words, services: editorServices())
        #expect(model.step == .words)
        #expect(model.previousStep == nil)
        model.continueFromWords()
        #expect(model.step == .details)
        #expect(model.previousStep == .words)
    }

    @Test func saveWithNothingFilledInShowsTheProblems() async throws {
        let services = editorServices()
        let model = await loadedEditor(services: services)
        let before = try await services.closet.garments().count
        #expect(!model.showsProblems)
        #expect(await model.save(in: services.closet) == nil)
        #expect(model.showsProblems)
        #expect(model.problems.fields == [.name, .category])
        #expect(model.problemCheckCount == 1)
        #expect(try await services.closet.garments().count == before)
    }

    @Test func problemsClearAsSheFixesThem() async {
        let services = editorServices()
        let model = await loadedEditor(services: services)
        _ = await model.save(in: services.closet)
        model.details.name = "Sage cardigan"
        #expect(model.problems.fields == [.category])
        model.details.category = .layer
        #expect(model.problems.isEmpty)
    }

    @Test func tooLongFieldsAreRefusedByField() async {
        let services = editorServices()
        let model = await loadedEditor(services: services)
        model.details = GarmentDetails(name: "Coat", category: .layer, brand: String(repeating: "b", count: 41))
        #expect(await model.save(in: services.closet) == nil)
        #expect(model.problems[.brand] == .tooLong(maximum: 40))
        #expect(model.problems[.name] == nil)
    }

    @Test func addByWordsEndToEnd() async throws {
        let services = editorServices()
        let model = await loadedEditor(services: services)
        model.describeInWords()
        #expect(model.step == .words)
        model.description = "Sage green cardigan with gold buttons, soft and cozy"
        await model.suggest(using: services.descriptions)
        #expect(model.suggestionState == .loaded)
        #expect(model.suggestions.count == 5)
        for row in model.suggestions { model.decide(.accepted, for: row.id) }
        model.continueFromWords()
        #expect(model.step == .details)
        #expect(model.details.name == "Sage cardigan")
        #expect(model.details.category == .layer)
        #expect(model.details.colors == [.green])
        #expect(model.details.colorNote == "Sage")
        #expect(model.details.warmth == .warm)
        #expect(model.details.notes == "Gold buttons")

        let saved = try #require(await model.save(in: services.closet))
        guard case .added(let garment) = saved else {
            Issue.record("Expected a new piece")
            return
        }
        let stored = try await services.closet.garment(garment.id)
        #expect(stored.name == "Sage cardigan")
        #expect(stored.addedAt == ClosetTestTime.now)
        #expect(stored.isInCloset)
        // Newest first, so it heads the grid.
        #expect(try await services.closet.garments().first?.id == garment.id)
        // Saved: the draft is gone.
        #expect(try await services.drafts.drafts().isEmpty)
    }

    @Test func nothingIsFilledInUntilSheAccepts() async throws {
        let services = editorServices()
        let model = await loadedEditor(firstStep: .words, services: services)
        model.description = "Sage green cardigan with gold buttons"
        await model.suggest(using: services.descriptions)
        // Accept the kind, skip the name, leave the rest.
        let name = try #require(model.suggestions.first { if case .name = $0.suggestion { true } else { false } })
        let kind = try #require(model.suggestions.first { if case .category = $0.suggestion { true } else { false } })
        model.decide(.skipped, for: name.id)
        model.decide(.accepted, for: kind.id)
        model.continueFromWords()
        #expect(model.details.name.isEmpty)
        #expect(model.details.category == .layer)
        #expect(model.details.colors.isEmpty)
        #expect(model.details.notes.isEmpty)
    }

    @Test func choosingTheSameDecisionAgainUndoesIt() async {
        let services = editorServices()
        let model = await loadedEditor(firstStep: .words, services: services)
        model.description = "navy jeans"
        await model.suggest(using: services.descriptions)
        model.decide(.accepted, for: 0)
        #expect(model.suggestions[0].decision == .accepted)
        model.decide(.accepted, for: 0)
        #expect(model.suggestions[0].decision == nil)
        model.decide(.skipped, for: 0)
        #expect(model.suggestions[0].decision == .skipped)
    }

    @Test func comingBackToWordsDoesntUndoHerEdits() async {
        let services = editorServices()
        let model = await loadedEditor(firstStep: .words, services: services)
        model.description = "navy jeans"
        await model.suggest(using: services.descriptions)
        for row in model.suggestions { model.decide(.accepted, for: row.id) }
        model.continueFromWords()
        #expect(model.details.name == "Navy jeans")
        model.details.name = "Work jeans"
        model.goBack()
        #expect(model.step == .words)
        model.continueFromWords()
        #expect(model.details.name == "Work jeans")
    }

    @Test func suggestNeedsWordsWithinTheLimit() async {
        let services = editorServices()
        let model = await loadedEditor(firstStep: .words, services: services)
        await model.suggest(using: services.descriptions)
        #expect(model.descriptionProblem == .empty)
        #expect(model.suggestionState == .idle)
        model.description = String(repeating: "w", count: 1_001)
        await model.suggest(using: services.descriptions)
        #expect(model.descriptionProblem == .tooLong(maximum: 1_000))
        model.description = "jeans"
        await model.suggest(using: services.descriptions)
        #expect(model.descriptionProblem == nil)
        #expect(model.suggestionState == .loaded)
    }

    @Test func wordsWithNothingToSuggestSayItPlainly() async {
        let services = editorServices()
        let model = await loadedEditor(firstStep: .words, services: services)
        model.description = "my favourite thing"
        await model.suggest(using: services.descriptions)
        #expect(model.suggestionState == .loaded)
        #expect(model.suggestions.isEmpty)
    }

    @Test func aPhotoMovesOnToTheForm() async {
        let services = editorServices()
        let model = await loadedEditor(services: services)
        await model.choosePhoto(from: .camera, using: services.photos)
        #expect(model.step == .details)
        #expect(model.details.photo == StandInPhotoIntake.samplePhoto)
        #expect(model.photoState == .idle)
        #expect(model.previousStep == .choose)
        #expect(model.isDirty)
        model.goBack()
        #expect(model.step == .choose)
    }

    @Test func aPhotoThatCantBeReadChangesNothing() async {
        let services = editorServices(behavior: .photoFails)
        let model = await loadedEditor(services: services)
        await model.choosePhoto(from: .library, using: services.photos)
        #expect(model.photoState == .failed)
        #expect(model.step == .choose)
        #expect(model.details.photo == .noPhoto)
        model.clearPhotoProblem()
        #expect(model.photoState == .idle)
        model.describeInWords()
        #expect(model.step == .words)
    }

    @Test func aSaveThatFailsKeepsHerWork() async throws {
        let services = editorServices(behavior: .storesFail)
        let model = await loadedEditor(services: services)
        #expect(model.phase == .editing)
        model.details = GarmentDetails(name: "Sage cardigan", category: .layer)
        #expect(await model.save(in: services.closet) == nil)
        #expect(model.saveFailed)
        #expect(model.details.name == "Sage cardigan")
        // Typing again clears the note.
        model.details.name = "Sage cardi"
        #expect(!model.saveFailed)
    }
}

/// Edit: the same form, filled in with the piece (Phase 7b).
@MainActor
struct EditPieceModelTests {
    @Test func opensFilledInWithThePiece() async {
        let model = await loadedEditor(.garment("g-navy-trousers"), services: editorServices())
        #expect(model.phase == .editing)
        #expect(model.step == .details)
        #expect(model.details.name == "Navy dress pants")
        #expect(model.details.category == .bottom)
        #expect(model.savedName == "Navy dress pants")
        #expect(!model.isDirty)
        #expect(model.previousStep == nil)
    }

    @Test func saveUpdatesThePieceAndKeepsItsStates() async throws {
        let services = editorServices(laundry: .some)
        let model = await loadedEditor(.garment("g-navy-trousers"), services: services)
        let before = try await services.closet.garment("g-navy-trousers")
        model.details.name = "Navy work trousers"
        model.details.fit = .fitted
        let saved = try #require(await model.save(in: services.closet))
        #expect(saved == .updated(saved.garment))
        let after = try await services.closet.garment("g-navy-trousers")
        #expect(after.name == "Navy work trousers")
        #expect(after.fit == .fitted)
        #expect(after.wornOn == before.wornOn)
        #expect(after.laundry == before.laundry)
        #expect(after.ownership == before.ownership)
        #expect(after.addedAt == before.addedAt)
        #expect(!model.isDirty)
    }

    @Test func dirtyOnlyWhileItDiffers() async {
        let model = await loadedEditor(.garment("g-navy-trousers"), services: editorServices())
        model.details.name = "Navy work trousers"
        #expect(model.isDirty)
        model.details.name = "Navy dress pants"
        #expect(!model.isDirty)
        model.toggleSeason(.summer)
        #expect(model.isDirty)
        model.toggleSeason(.summer)
        #expect(!model.isDirty)
    }

    @Test func aPieceThatsGoneOrFailsToLoad() async {
        let gone = await loadedEditor(.garment("g-nothing"), services: editorServices())
        #expect(gone.phase == .gone)
        let deleted = await loadedEditor(.garment("g-gray-leggings"), services: editorServices())
        #expect(deleted.phase == .gone)
        let failed = await loadedEditor(.garment("g-navy-trousers"), services: editorServices(behavior: .storesFail))
        #expect(failed.phase == .failed)
    }

    @Test func coloursKeepTheOrderSheTappedThem() async {
        let model = await loadedEditor(.garment("g-navy-trousers"), services: editorServices())
        #expect(model.details.colors == [.navy])
        model.toggleColor(.white)
        model.toggleColor(.navy)
        model.toggleColor(.navy)
        #expect(model.details.colors == [.white, .navy])
    }
}

/// Drafts: written as she goes, offered next time, resumed or discarded (PRD §7.3, FR-31).
@MainActor
struct GarmentDraftModelTests {
    @Test func changesAreWrittenAfterAPause() async throws {
        let services = editorServices()
        let model = await loadedEditor(draftSaveDelay: .milliseconds(100), services: services)
        model.details.name = "S"
        model.details.name = "Sa"
        model.details.name = "Sage"
        #expect(try await services.drafts.drafts().isEmpty)
        await model.settleDraft()
        #expect(model.draftWrites == 1)
        #expect(try await services.drafts.draft(for: .newPiece)?.details.name == "Sage")
    }

    @Test func aDraftWithNothingToKeepIsRemoved() async throws {
        let services = editorServices()
        let model = await loadedEditor(services: services)
        model.details.name = "Sage"
        await model.settleDraft()
        #expect(try await services.drafts.drafts().count == 1)
        model.details.name = ""
        await model.settleDraft()
        #expect(try await services.drafts.drafts().isEmpty)
    }

    /// The app is closed mid-add: a new screen model on the same store stands in for the next
    /// launch, since Stage A drafts live in memory.
    @Test func closingMidAddOffersResumeNextTime() async throws {
        let services = editorServices()
        let first = await loadedEditor(firstStep: .words, draftSaveDelay: .seconds(60), services: services)
        first.description = "navy jeans"
        await first.suggest(using: services.descriptions)
        for row in first.suggestions { first.decide(.accepted, for: row.id) }
        first.continueFromWords()
        // Going to the background writes at once, without waiting for the pause.
        await first.saveDraftNow()

        let next = await loadedEditor(services: services)
        #expect(next.phase == .offeringResume)
        #expect(next.pendingDraft?.details.name == "Navy jeans")
        next.resume()
        #expect(next.phase == .editing)
        #expect(next.step == .details)
        #expect(next.details.name == "Navy jeans")
        #expect(next.description == "navy jeans")
        #expect(next.previousStep == .words)
        #expect(next.isDirty)
    }

    @Test func discardStartsFresh() async throws {
        let services = editorServices(draft: .add)
        let model = await loadedEditor(services: services)
        #expect(model.phase == .offeringResume)
        await model.discardPendingDraft()
        #expect(model.phase == .editing)
        #expect(model.step == .choose)
        #expect(model.details == .blank)
        #expect(try await services.drafts.drafts().isEmpty)
    }

    @Test func resumeFromClosetSkipsTheQuestion() async {
        let model = await loadedEditor(resumesDraft: true, services: editorServices(draft: .add))
        #expect(model.phase == .editing)
        #expect(model.step == .details)
        #expect(model.details.name == "Sage cardigan")
        #expect(model.previousStep == .words)
    }

    @Test func anEditDraftIsOfferedOnThatPieceOnly() async {
        let services = editorServices(draft: .edit)
        let other = await loadedEditor(.garment("g-pink-blouse"), services: services)
        #expect(other.phase == .editing)
        let new = await loadedEditor(services: services)
        #expect(new.phase == .editing)
        let trousers = await loadedEditor(.garment("g-navy-trousers"), services: services)
        #expect(trousers.phase == .offeringResume)
        trousers.resume()
        #expect(trousers.details.name == "Navy work trousers")
        #expect(trousers.isDirty)
    }

    @Test func cancelThrowsTheDraftAway() async throws {
        let services = editorServices()
        let model = await loadedEditor(services: services)
        model.details.name = "Sage"
        await model.settleDraft()
        await model.discardChanges()
        #expect(try await services.drafts.drafts().isEmpty)
    }

    @Test func aDraftNeverChangesTheCloset() async throws {
        let services = editorServices()
        let model = await loadedEditor(.garment("g-navy-trousers"), services: services)
        model.details.name = "Navy work trousers"
        await model.saveDraftNow()
        #expect(try await services.closet.garment("g-navy-trousers").name == "Navy dress pants")
        #expect(try await services.drafts.draft(for: .garment("g-navy-trousers"))?.details.name == "Navy work trousers")
    }
}

/// Closet offers a waiting draft at the top (Phase 7b).
@MainActor
struct ClosetDraftTests {
    @Test func offersTheWaitingDraft() async {
        let model = ClosetModel()
        await model.load(from: editorServices(draft: .add), now: ClosetTestTime.now)
        #expect(model.draft?.target == .newPiece)
        let none = ClosetModel()
        await none.load(from: editorServices(), now: ClosetTestTime.now)
        #expect(none.draft == nil)
    }

    @Test func aDraftForAPieceThatsGoneIsntOffered() async throws {
        let services = editorServices(draft: .edit)
        try await services.closet.delete("g-navy-trousers", at: ClosetTestTime.now)
        let model = ClosetModel()
        await model.load(from: services, now: ClosetTestTime.now)
        #expect(model.draft == nil)
        // It stays, in case Undo brings the piece back.
        #expect(try await services.drafts.drafts().count == 1)
    }

    @Test func discardRemovesIt() async throws {
        let services = editorServices(draft: .add)
        let model = ClosetModel()
        await model.load(from: services, now: ClosetTestTime.now)
        await model.discardDraft(in: services.drafts)
        #expect(model.draft == nil)
        #expect(try await services.drafts.drafts().isEmpty)
    }

    @Test func theCardSaysWhatsWaiting() throws {
        let add = try #require(
            FixtureDrafts.draft(
                .add, in: FixtureSet.demo.data(now: ClosetTestTime.now, calendar: ClosetTestTime.calendar),
                now: ClosetTestTime.now))
        #expect(DraftResumeText.message(for: add) == "Sage cardigan isn’t in your closet yet.")
        #expect(
            DraftResumeText.age(of: add, now: ClosetTestTime.now, locale: ClosetTestTime.locale)
                == "Last changed 5 minutes ago")
        var unnamed = add
        unnamed.details.name = ""
        #expect(DraftResumeText.message(for: unnamed) == "The piece you started adding isn’t in your closet yet.")
        let edit = try #require(
            FixtureDrafts.draft(
                .edit, in: FixtureSet.demo.data(now: ClosetTestTime.now, calendar: ClosetTestTime.calendar),
                now: ClosetTestTime.now))
        #expect(DraftResumeText.message(for: edit) == "Your changes to Navy dress pants aren’t saved yet.")
        var fresh = edit
        fresh.savedAt = ClosetTestTime.now
        #expect(
            DraftResumeText.age(of: fresh, now: ClosetTestTime.now, locale: ClosetTestTime.locale)
                == "Last changed just now")
    }

    @Test func problemsReadAsFixes() {
        #expect(GarmentEditorText.problem(.empty, in: .name) == "Give it a name.")
        #expect(GarmentEditorText.problem(.missingChoice, in: .category) == "Choose what kind of piece it is.")
        #expect(GarmentEditorText.problem(.tooLong(maximum: 40), in: .brand) == "Keep this to 40 characters.")
        #expect(GarmentEditorText.problem(.controlCharacters, in: .sizeLabel) == "Keep this on one line.")
        #expect(
            GarmentEditorText.problemsAnnouncement(GarmentProblems([.name: .empty, .category: .missingChoice]))
                == "Not saved yet. Check Name and Kind.")
    }
}
