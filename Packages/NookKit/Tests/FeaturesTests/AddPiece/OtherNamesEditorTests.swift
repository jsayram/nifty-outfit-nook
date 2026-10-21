import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Other names and the type on Add a piece and Edit (Phase 21c, PRD §7.6), and finding a piece by
/// them in Closet.
@MainActor
struct OtherNamesEditorTests {
    private func filledIn(_ services: NookServices) async -> GarmentEditorModel {
        let model = await loadedEditor(firstStep: .words, services: services)
        model.continueFromWords()
        model.details.name = "Sage cardigan"
        model.chooseCategory(.layer)
        return model
    }

    @Test func addingAndRemovingOtherNames() async {
        let model = await filledIn(editorServices())
        model.newOtherName = "  Green cardigan "
        #expect(model.addOtherName())
        #expect(model.details.otherNames == ["Green cardigan"])
        #expect(model.newOtherName.isEmpty)

        // The same name again, or the piece's own name, is refused with a reason.
        model.newOtherName = "green CARDIGAN"
        #expect(!model.addOtherName())
        #expect(model.otherNameProblem == .duplicate)
        #expect(GarmentEditorText.problem(.duplicate, in: .otherNames) == "It already has that name.")
        // Typing again clears the problem.
        model.newOtherName = "Cozy one"
        #expect(model.otherNameProblem == nil)
        #expect(model.addOtherName())
        model.newOtherName = ""
        #expect(!model.addOtherName())
        #expect(GarmentEditorText.problem(.empty, in: .otherNames) == "Type a name first.")

        model.removeOtherName("Green cardigan")
        #expect(model.details.otherNames == ["Cozy one"])
        #expect(GarmentEditorText.removeOtherName("Cozy one") == "Remove Cozy one")
    }

    @Test func saveKeepsOtherNamesAndTheTypeAndAddsATypedName() async throws {
        let services = editorServices()
        let model = await filledIn(services)
        model.newOtherName = "Green cardigan"
        model.addOtherName()
        model.chooseSubKind(.cardigan)
        // Typed but not added yet: Save adds it rather than lose it.
        model.newOtherName = "Cozy one"
        let saved = try #require(await model.save(in: services.closet))
        #expect(saved.garment.otherNames == ["Green cardigan", "Cozy one"])
        #expect(saved.garment.subKind == .cardigan)
        let stored = try await services.closet.garment(saved.garment.id)
        #expect(stored.otherNames == ["Green cardigan", "Cozy one"] && stored.subKind == .cardigan)
    }

    @Test func aTypedNameThatCantBeAddedStopsSave() async throws {
        let services = editorServices()
        let model = await filledIn(services)
        let before = try await services.closet.garments().count
        model.newOtherName = "Sage cardigan"
        #expect(await model.save(in: services.closet) == nil)
        #expect(model.problems.fields == [.otherNames])
        #expect(model.otherNameProblem == .duplicate)
        #expect(try await services.closet.garments().count == before)
    }

    @Test func typesFollowTheKind() async {
        let model = await loadedEditor(firstStep: .words, services: editorServices())
        model.continueFromWords()
        // No kind yet: no types to pick.
        #expect(model.subKindChoices.isEmpty)
        model.chooseCategory(.shoes)
        #expect(model.subKindChoices == [.flats, .heels, .sneakers, .loafers, .boots, .sandals])
        model.chooseSubKind(.loafers)
        // Another kind takes away a type that doesn't belong to it.
        model.chooseCategory(.layer)
        #expect(model.details.subKind == nil)
        model.chooseSubKind(.blazer)
        model.chooseCategory(.layer)
        #expect(model.details.subKind == .blazer)
        model.chooseSubKind(nil)
        #expect(model.details.subKind == nil)
        model.chooseCategory(.dress)
        #expect(model.subKindChoices.isEmpty)
        #expect(GarmentSubKind.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test func editShowsAndKeepsThem() async throws {
        let services = editorServices()
        try await services.closet.update("g-navy-trousers") {
            $0.otherNames = ["Interview pants"]
            $0.subKind = .trousers
        }
        let model = await loadedEditor(.garment("g-navy-trousers"), services: services)
        #expect(model.details.otherNames == ["Interview pants"])
        #expect(model.details.subKind == .trousers)
        model.removeOtherName("Interview pants")
        #expect(model.isDirty)
        let saved = try #require(await model.save(in: services.closet))
        #expect(saved.garment.otherNames.isEmpty && saved.garment.subKind == .trousers)
    }

    /// Other names are part of the draft, so closing the app keeps them.
    @Test func theDraftKeepsThem() async throws {
        let services = editorServices()
        let model = await filledIn(services)
        model.newOtherName = "Cozy one"
        model.addOtherName()
        model.chooseSubKind(.cardigan)
        await model.saveDraftNow()
        let next = await loadedEditor(resumesDraft: true, services: services)
        #expect(next.details.otherNames == ["Cozy one"] && next.details.subKind == .cardigan)
    }

    @Test func closetFindsAPieceByItsOtherNamesAndType() async throws {
        let services = editorServices()
        try await services.closet.update("g-navy-trousers") {
            $0.otherNames = ["Interview pants"]
            $0.subKind = .trousers
        }
        let closet = ClosetModel(searchDelay: .zero)
        await closet.load(from: services)
        closet.searchText = "interview"
        closet.applySearchNow()
        #expect(closet.shown.map(\.id) == ["g-navy-trousers"])
        closet.searchText = "Trousers"
        closet.applySearchNow()
        #expect(closet.shown.map(\.id).contains("g-navy-trousers"))
    }

    @Test func garmentDetailShowsThem() async throws {
        var garment = try await editorServices().closet.garment("g-navy-trousers")
        func text() -> GarmentDetailText {
            GarmentDetailText(
                garment: garment, tracksLaundry: false, repeatWindow: .oneWeek, now: TestTime.now,
                calendar: TestTime.calendar, locale: TestTime.locale)
        }
        #expect(text().otherNames == nil && text().subKind == nil)
        garment.otherNames = ["Interview pants", "Navy work pants"]
        garment.subKind = .trousers
        #expect(text().otherNames == "Interview pants, Navy work pants")
        #expect(text().subKind == "Trousers")
    }
}
