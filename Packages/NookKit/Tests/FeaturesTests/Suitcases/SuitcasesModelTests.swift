import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Suitcases (Phase 13): favourites, choosing the source, "+ Add a suitcase", and the words.
@MainActor
struct SuitcasesModelTests {
    private let now = ClosetTestTime.now

    private func services(_ set: FixtureSet = .demo, source: FixtureSourceState? = nil) -> NookServices {
        FixtureServices.make(set: set, source: source, now: now, calendar: ClosetTestTime.calendar)
    }

    private func loaded(_ services: NookServices) async -> SuitcasesModel {
        let model = SuitcasesModel()
        await model.load(from: services, now: now)
        return model
    }

    @Test func demoShowsThreeFavouritesSeeAllAndTheMainCloset() async {
        // RD-09.1: five active suitcases, the three most recently used first.
        let model = await loaded(services())
        #expect(model.phase == .loaded)
        #expect(model.favorites.map(\.name) == ["Jose's house", "Weekend", "Gym"])
        #expect(model.others.map(\.name) == ["Spring trip", "Beach"])
        #expect(model.shelf.showsSeeAll)
        #expect(model.shelf.archived.map(\.name) == ["Old dorm"])
        #expect(model.chosen == .mainCloset)
        #expect(model.closetCount == 17)
        #expect(!model.sourceWentAway)
    }

    @Test func emptyHasNoSuitcasesButTheMainCloset() async {
        let model = await loaded(services(.empty))
        #expect(!model.hasSuitcases)
        #expect(model.favorites.isEmpty)
        #expect(model.chosen == .mainCloset)
    }

    @Test func countsOnlyPiecesInHerCloset() async throws {
        // LR-16.1: a piece she no longer has stays linked but doesn't count.
        let services = services()
        try await services.closet.update("g-lace-top") { $0.ownership = .noLongerOwned }
        let model = await loaded(services)
        let jose = try #require(model.suitcase("s-jose"))
        #expect(jose.garmentIDs.contains("g-lace-top"))
        #expect(model.pieceCount(of: jose) == 4)
    }

    @Test func choosingASuitcaseRemembersItAndMakesItAFavourite() async throws {
        // FR-67, RD-09.2
        let services = services()
        let model = await loaded(services)
        let choice = try await model.choose(.suitcase("s-beach"), in: services, now: now)
        #expect(choice == .chosen(previous: .mainCloset))
        #expect(model.isChosen(.suitcase("s-beach")))
        // The order stays put while she's on the screen...
        #expect(model.favorites.map(\.name) == ["Jose's house", "Weekend", "Gym"])
        #expect(try await services.profile.profile().remembered.source == .suitcase("s-beach"))
        // ...and next time Beach is the first favourite.
        let next = await loaded(services)
        #expect(next.favorites.first?.name == "Beach")
        #expect(try await model.choose(.suitcase("s-beach"), in: services, now: now) == .unchanged)
    }

    @Test func anEmptySuitcaseIsNotChosen() async throws {
        let services = services()
        let model = await loaded(services)
        let choice = try await model.choose(.suitcase("s-spring"), in: services, now: now)
        guard case .empty(let suitcase) = choice else {
            Issue.record("Expected empty, got \(choice)")
            return
        }
        #expect(suitcase.id == "s-spring")
        #expect(model.chosen == .mainCloset)
        #expect(try await services.profile.profile().remembered.source == .mainCloset)
    }

    @Test func aRememberedSuitcaseThatWentAwayShowsTheMainCloset() async throws {
        // PRD §7.7: archived since, so browsing goes back to the main closet, and a line says so.
        let services = services(source: .suitcase)
        try await services.suitcases.update("s-jose") { $0.isArchived = true }
        let model = await loaded(services)
        #expect(model.chosen == .mainCloset)
        #expect(model.sourceWentAway)
    }

    @Test(arguments: [0, 1, 2, 3, 5])
    func addingASuitcaseShowsItAtOnce(existing: Int) async throws {
        // LR-17.2, RD-09.1
        let suitcases = (0..<existing).map {
            Suitcase(id: Suitcase.ID("s-\($0)"), name: "Case \($0)", createdAt: ClosetTestTime.day(-10 - $0))
        }
        var data = FixtureSet.demo.data(now: now, calendar: ClosetTestTime.calendar)
        data.suitcases = suitcases
        let services = NookServicesStub.make(data: data)
        let model = await loaded(services)
        #expect(model.favorites.count == min(existing, 3))
        #expect(model.shelf.showsSeeAll == (existing > 3))
        let made = try await model.create(name: "Beach week", icon: .backpack, in: services, now: now)
        #expect(made.icon == .backpack)
        #expect(model.shelf.all.contains { $0.id == made.id })
        #expect(model.nameProblem("beach WEEK") == .duplicate)
        #expect(model.nameProblem("  ") == .empty)
        #expect(model.nameProblem("Ski trip") == nil)
    }

    @Test func searchMatchesNames() async {
        let model = await loaded(services())
        model.searchText = "jose"
        #expect(model.matching(model.favorites).map(\.name) == ["Jose's house"])
        model.searchText = "nothing like it"
        #expect(model.matching(model.favorites + model.others).isEmpty)
    }

    @Test func lastUsedWords() {
        let calendar = ClosetTestTime.calendar
        let locale = ClosetTestTime.locale
        func used(_ days: Int?) -> String {
            SuitcasesText.lastUsed(days.map { ClosetTestTime.day(-$0) }, now: now, calendar: calendar, locale: locale)
        }
        #expect(used(nil) == "Not used yet")
        #expect(used(0) == "Used today")
        #expect(used(1) == "Used yesterday")
        #expect(used(4) == "Used 4 days ago")
        #expect(used(9) == "Used last week")
        #expect(used(20) == "Used 2 weeks ago")
        #expect(used(40) == "Last used Sep 4")
        #expect(
            SuitcasesText.rowDetail(pieceCount: 5, lastUsed: "Used today", isChosen: false) == "5 pieces · Used today")
        #expect(SuitcasesText.rowDetail(pieceCount: 1, lastUsed: "x", isChosen: true) == "Style Me source · 1 piece")
        #expect(SuitcasesText.closetPieces(17) == "All 17 pieces")
        #expect(SuitcasesText.closetPieces(1) == "1 piece")
        #expect(SuitcasesText.closetPieces(0) == "Empty")
    }
}

/// Services from fixture data that's been changed by a test.
enum NookServicesStub {
    static func make(data: FixtureData) -> NookServices {
        var services = FixtureServices.make(set: .demo, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
        services.closet = InMemoryClosetStore(garments: data.garments, calendar: ClosetTestTime.calendar)
        services.suitcases = InMemorySuitcaseStore(suitcases: data.suitcases)
        services.profile = InMemoryProfileStore(profile: data.profile)
        return services
    }
}
