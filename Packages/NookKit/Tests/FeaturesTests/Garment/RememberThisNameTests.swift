import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Remember this name (PRD §7.6) on garment detail, after opening a piece from Possible matches.
@MainActor
struct RememberThisNameTests {
    private func model(
        _ id: Garment.ID = "g-navy-trousers", remembering: String?, services: NookServices
    ) async -> GarmentDetailModel {
        let model = GarmentDetailModel(garmentID: id, remembering: remembering)
        await model.load(from: services, now: TestTime.now)
        return model
    }

    @Test func rememberKeepsHerWordsAsAnotherName() async throws {
        let services = garmentTestServices()
        let detail = await model(remembering: "navy party pants", services: services)
        #expect(detail.offersToRemember)
        #expect(detail.rememberText == "navy party pants")
        // She tidies the words before keeping them.
        detail.rememberText = "  party pants "
        let kept = try await detail.remember(in: services.closet)
        #expect(kept == "party pants")
        #expect(!detail.offersToRemember)
        #expect(detail.garment?.otherNames.last == "party pants")
        let stored = try await services.closet.garment("g-navy-trousers")
        #expect(stored.otherNames.last == "party pants")

        // Closet finds it by those words now, as a real result.
        let closet = await loadedClosetModel(.demo)
        closet.show(
            try await services.closet.garments(), suitcases: try await services.suitcases.suitcases(),
            profile: try await services.profile.profile(), now: TestTime.now)
        closet.searchText = "party pants"
        closet.applySearchNow()
        #expect(closet.shown.map(\.id) == ["g-navy-trousers"])
    }

    @Test func undoTakesTheNameOffAgain() async throws {
        let services = garmentTestServices()
        let detail = await model(remembering: "party pants", services: services)
        let before = try await services.closet.garment("g-navy-trousers").otherNames
        let kept = try #require(try await detail.remember(in: services.closet))
        try await detail.forget(kept, in: services.closet)
        #expect(try await services.closet.garment("g-navy-trousers").otherNames == before)
        #expect(detail.garment?.otherNames == before)
    }

    @Test func notNowKeepsNothing() async throws {
        let services = garmentTestServices()
        let detail = await model(remembering: "party pants", services: services)
        let before = try await services.closet.garment("g-navy-trousers")
        detail.declineToRemember()
        #expect(!detail.offersToRemember)
        #expect(try await services.closet.garment("g-navy-trousers") == before)
    }

    @Test func onlyOfferedFromPossibleMatches() async {
        let detail = await model(remembering: nil, services: garmentTestServices())
        #expect(!detail.offersToRemember)
    }

    @Test func wordsThatAreAlreadyItsNameArentOffered() async {
        let detail = await model(remembering: "navy DRESS pants", services: garmentTestServices())
        #expect(!detail.offersToRemember)
    }

    @Test func aPieceWithAFullListIsntOffered() async throws {
        let services = garmentTestServices()
        _ = try await services.closet.update("g-navy-trousers") { garment in
            garment.otherNames = (1...GarmentRules.otherNamesMaximumCount).map { "Name \($0)" }
        }
        let detail = await model(remembering: "party pants", services: services)
        #expect(!detail.offersToRemember)
    }

    @Test func problemsAreSaidAndTypingClearsThem() async throws {
        let services = garmentTestServices()
        let detail = await model(remembering: "party pants", services: services)
        detail.rememberText = "   "
        #expect(try await detail.remember(in: services.closet) == nil)
        #expect(detail.rememberProblem == .empty)
        #expect(detail.offersToRemember)
        detail.rememberText = "Navy dress pants"
        #expect(detail.rememberProblem == nil)
        #expect(try await detail.remember(in: services.closet) == nil)
        #expect(detail.rememberProblem == .duplicate)
        detail.rememberText = String(repeating: "a", count: GarmentRules.otherNameMaximum + 1)
        #expect(try await detail.remember(in: services.closet) == nil)
        #expect(detail.rememberProblem == .tooLong(maximum: GarmentRules.otherNameMaximum))
        #expect(try await services.closet.garment("g-navy-trousers").otherNames.isEmpty)
    }

    @Test func aPieceNotInHerClosetIsntOffered() async throws {
        let services = garmentTestServices()
        _ = try await services.closet.update("g-navy-trousers") { $0.ownership = .noLongerOwned }
        let detail = await model(remembering: "party pants", services: services)
        #expect(!detail.offersToRemember)
    }
}
