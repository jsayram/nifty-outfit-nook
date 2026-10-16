import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Services for Make your own look on the fixed test clock, with a stylist that counts calls.
@MainActor
func builderServices(
    _ set: FixtureSet = .demo, behavior: FixtureBehavior = .normal, laundry: FixtureLaundryState? = nil,
    draft: FixtureDraftState? = nil, stylist: ScriptedStylist? = nil
) -> NookServices {
    var services = FixtureServices.make(
        set: set, behavior: behavior, laundry: laundry, draft: draft, now: ClosetTestTime.now,
        calendar: ClosetTestTime.calendar)
    if let stylist { services.stylist = stylist }
    return services
}

/// A Make your own look model loaded from `services`, with numbered look IDs.
@MainActor
func loadedBuilder(
    startingWith start: Garment.ID? = nil, services: NookServices = builderServices()
) async -> LookBuilderModel {
    var next = 0
    let model = LookBuilderModel(
        startingPieceID: start, now: { ClosetTestTime.now },
        makeLookID: {
            next += 1
            return Look.ID("made-\(next)")
        })
    await model.load(from: services)
    return model
}

/// Make your own look (LR-08.3, LR-08.4, FR-32, PRD §7.3).
@MainActor
struct LookBuilderModelTests {
    // MARK: Starting

    /// From a garment's Style with this, the look starts with that piece.
    @Test func startsWithThePieceFromStyleWithThis() async {
        let model = await loadedBuilder(startingWith: "g-navy-trousers")
        #expect(model.phase == .loaded)
        #expect(model.pieceIDs == ["g-navy-trousers"])
        #expect(!model.canSave)
        #expect(model.problems == [.tooFewPieces, .needsMainPieces])
        #expect(model.offeredDraft == nil)
    }

    /// "+ Make your own" starts empty.
    @Test func startsEmptyFromSavedLooks() async {
        let model = await loadedBuilder()
        #expect(model.pieceIDs.isEmpty)
        #expect(model.pieces.isEmpty)
    }

    /// A piece she can't wear today isn't put in the look.
    @Test func aPieceInTheWashIsNotStartedWith() async {
        let model = await loadedBuilder(startingWith: "g-lace-top", services: builderServices(laundry: .full))
        #expect(model.pieceIDs.isEmpty)
        #expect(!model.pickerScope().garmentIDs.contains("g-lace-top"))
    }

    // MARK: Building

    @Test func addRemoveUndoAndRedo() async {
        let model = await loadedBuilder(startingWith: "g-navy-trousers")
        model.add("g-pink-blouse")
        model.add("g-nude-flats")
        #expect(model.pieces.map(\.id) == ["g-pink-blouse", "g-navy-trousers", "g-nude-flats"])
        #expect(model.canSave)

        // One of each kind: another top takes the blouse's place.
        model.add("g-cream-sweater")
        #expect(model.pieceIDs == ["g-navy-trousers", "g-nude-flats", "g-cream-sweater"])
        model.remove("g-nude-flats")
        #expect(model.pieceIDs == ["g-navy-trousers", "g-cream-sweater"])

        model.undo()
        #expect(model.pieceIDs == ["g-navy-trousers", "g-nude-flats", "g-cream-sweater"])
        model.undo()
        #expect(model.pieceIDs == ["g-navy-trousers", "g-pink-blouse", "g-nude-flats"])
        model.redo()
        #expect(model.pieceIDs == ["g-navy-trousers", "g-nude-flats", "g-cream-sweater"])
        #expect(model.canUndo && model.canRedo)
        // A new change clears Redo.
        model.add("g-tan-loafers")
        #expect(!model.canRedo)
    }

    @Test func checksTheLookBeforeSaving() async {
        let model = await loadedBuilder(startingWith: "g-pink-blouse")
        model.add("g-nude-flats")
        #expect(model.problems == [.needsMainPieces])
        #expect(!model.canSave)
        #expect(
            LookBuilderText.line(for: .needsMainPieces, garments: model.garments)
                == "A look needs a top and a bottom, or a dress.")
        model.add("g-olive-trousers")
        #expect(model.problems.isEmpty)
        #expect(model.canSave)

        model.name = String(repeating: "a", count: NameRules.lookNameMaximum + 1)
        #expect(model.nameProblem == .tooLong(maximum: NameRules.lookNameMaximum))
        #expect(!model.canSave)
        model.name = "  "
        #expect(model.nameProblem == nil, "An empty name is filled in on save")
    }

    /// The picker offers what she can wear from the main closet, and marks what's in the look.
    @Test func thePickerOffersWhatSheCanWear() async {
        let model = await loadedBuilder(startingWith: "g-navy-trousers")
        let scope = model.pickerScope()
        #expect(scope.notes == ["g-navy-trousers": SwapText.inTheLook])
        #expect(scope.fixedKind == nil)
        // Away, not hers, not arrived, archived and deleted pieces aren't offered.
        for missing: Garment.ID in [
            "g-blue-dress", "g-camel-trench", "g-cream-crop", "g-black-skirt", "g-gray-leggings",
        ] {
            #expect(!scope.garmentIDs.contains(missing), "\(missing)")
        }
        // Grouped by kind, top to bottom.
        let kinds = scope.garmentIDs.compactMap { model.garments[$0]?.category }
        #expect(kinds == kinds.sorted())
    }

    // MARK: Saving

    /// LR-08.3: Save look puts a named look in Saved Looks, with no request.
    @Test func saveMakesANamedSavedLook() async throws {
        let stylist = ScriptedStylist()
        let services = builderServices(stylist: stylist)
        let model = await loadedBuilder(startingWith: "g-navy-trousers", services: services)
        model.add("g-pink-blouse")
        model.add("g-nude-flats")
        model.name = "Friday pink"
        let look = try await model.save(fallbackName: "Pink & navy")
        #expect(look.id == "made-1")
        #expect(look.name == "Friday pink")
        #expect(look.isSaved)
        #expect(look.isMadeByHer)
        #expect(look.source == .mainCloset)
        #expect(look.garmentIDs == ["g-pink-blouse", "g-navy-trousers", "g-nude-flats"])
        #expect(try await services.looks.look("made-1") == look)
        #expect(!model.hasUnsavedChanges)
        #expect(!model.canSave)
        #expect(await stylist.calls == 0)
        await model.settle()
        #expect(try await services.lookDrafts.draft() == nil, "Saving drops the draft")

        // More changes, then Save again: the same look is updated (PRD §7.3).
        model.add("g-tan-loafers")
        #expect(model.canSave)
        let again = try await model.save(fallbackName: "")
        #expect(again.id == "made-1")
        #expect(try await services.looks.look("made-1").garmentIDs.contains("g-tan-loafers"))
    }

    /// With no name typed, the look is named from its colours.
    @Test func anEmptyNameIsFilledIn() async throws {
        let model = await loadedBuilder(startingWith: "g-navy-trousers")
        model.add("g-pink-blouse")
        let fallback = YourLooksText.colourName(of: model.pieces, locale: ClosetTestTime.locale)
        #expect(fallback == "Pink & navy")
        let look = try await model.save(fallbackName: fallback ?? LookBuilderText.fallbackName)
        #expect(look.name == "Pink & navy")
        #expect(model.name == "Pink & navy")
        #expect(!model.hasUnsavedChanges)
    }

    /// FR-32: it works offline, since nothing is sent.
    @Test func worksOffline() async throws {
        let model = await loadedBuilder(startingWith: "g-navy-trousers", services: builderServices(behavior: .offline))
        model.add("g-pink-blouse")
        #expect(try await model.save(fallbackName: "Pink & navy").isSaved)
    }

    @Test func aStoreFailureShowsTheErrorState() async {
        let model = await loadedBuilder(services: builderServices(behavior: .storesFail))
        #expect(model.phase == .failed)
    }

    // MARK: Drafts

    /// LR-08.4: a half-built look is written as a draft, and offered again after the app closes
    /// (a new model on the same store stands in for the relaunch).
    @Test func aHalfBuiltLookSurvivesARelaunch() async throws {
        let services = builderServices()
        let first = await loadedBuilder(startingWith: "g-navy-trousers", services: services)
        first.add("g-pink-blouse")
        first.name = "Friday"
        await first.settle()
        let draft = try #require(try await services.lookDrafts.draft())
        #expect(draft.garmentIDs == ["g-navy-trousers", "g-pink-blouse"])
        #expect(draft.name == "Friday")

        let relaunched = await loadedBuilder(services: services)
        #expect(relaunched.offeredDraft == draft)
        #expect(LookBuilderText.draftMessage(draft) == "You started “Friday” with 2 pieces and didn’t save it.")
        relaunched.resumeDraft()
        #expect(relaunched.offeredDraft == nil)
        #expect(relaunched.pieceIDs == ["g-navy-trousers", "g-pink-blouse"])
        #expect(relaunched.name == "Friday")
        #expect(relaunched.canSave)
    }

    /// The fixture draft `-fixtures demo:draft=look` uses.
    @Test func theFixtureDraftIsOffered() async {
        let model = await loadedBuilder(services: builderServices(draft: .look))
        #expect(model.offeredDraft?.name == FixtureDrafts.lookDraftName)
        #expect(model.offeredDraft?.garmentIDs == ["g-pink-blouse", "g-navy-trousers"])
    }

    /// While a draft is offered it's kept, even if she changes the look; Start over drops it.
    @Test func startOverDropsTheDraft() async throws {
        let services = builderServices(draft: .look)
        let model = await loadedBuilder(startingWith: "g-cream-sweater", services: services)
        model.add("g-olive-trousers")
        await model.settle()
        #expect(try await services.lookDrafts.draft()?.name == FixtureDrafts.lookDraftName)
        model.discardOfferedDraft()
        await model.settle()
        let draft = try #require(try await services.lookDrafts.draft())
        #expect(draft.garmentIDs == ["g-cream-sweater", "g-olive-trousers"], "What's on screen is kept now")
        #expect(model.pieceIDs == ["g-cream-sweater", "g-olive-trousers"])
    }

    /// A draft with nothing in it isn't offered.
    @Test func anUnchangedDraftIsNotOffered() async throws {
        let services = builderServices()
        try await services.lookDrafts.save(
            LookDraft(garmentIDs: ["g-navy-trousers"], startingPieceID: "g-navy-trousers", savedAt: ClosetTestTime.now))
        let model = await loadedBuilder(services: services)
        #expect(model.offeredDraft == nil)
    }
}
