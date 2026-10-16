import Foundation
import Models
import Testing

@testable import Fixtures

/// A small hand-built closet for focused stylist tests.
private struct Closet: FixtureDataLike {
    var garments: [Garment]
    var suitcases: [Suitcase] = []
    var looks: [Look] = []
    var profile = Profile()
}

private func garment(
    _ id: Garment.ID,
    _ category: GarmentCategory,
    dressiness: Dressiness = .smart,
    occasions: Set<Occasion> = [.office]
) -> Garment {
    Garment(
        id: id, name: "Piece \(id)", category: category, dressiness: dressiness, occasions: occasions,
        addedAt: TestTime.day(-50))
}

struct MockStylistTests {
    private let demo = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)

    private func style(
        _ data: some FixtureDataLike,
        _ request: StyleRequest,
        stylist: MockStylist = MockStylist()
    ) async throws -> (StyleOutcome, StylingContext) {
        let context = try StylingContext.from(data, request: request)
        return (try await stylist.style(context), context)
    }

    @Test func demoOfficeGivesThreeValidVersions() async throws {
        let (outcome, context) = try await style(demo, makeRequest())
        guard case .complete(let result) = outcome else {
            Issue.record("Expected three versions, got \(outcome)")
            return
        }
        #expect(result.versions.map(\.version) == [.simple, .dressedUp, .somethingNew])
        #expect(ResultCheck.problems(in: result, for: context).isEmpty)
        // LR-05a.1: the other versions keep pieces from Simple.
        let simple = Set(result.simple?.garmentIDs ?? [])
        for look in result.versions.dropFirst() {
            #expect(!simple.isDisjoint(with: look.garmentIDs))
        }
    }

    @Test func isDeterministic() async throws {
        let (first, _) = try await style(demo, makeRequest())
        let (second, _) = try await style(demo, makeRequest())
        #expect(first == second)
    }

    @Test func somethingNewAddsOneIdeaWithMineAndOneIdea() async throws {
        // LR-05b.1
        let (outcome, _) = try await style(demo, makeRequest(pieceMode: .mineAndOneIdea))
        let somethingNew = try #require(outcome.result?.look(for: .somethingNew))
        #expect(somethingNew.ideas.count == 1)
        #expect(outcome.result?.versions.filter { $0.version != .somethingNew }.allSatisfy { $0.ideas.isEmpty } == true)
    }

    @Test func onlyMineNeverAddsAnIdea() async throws {
        // LR-03.4 and LR-05b.2
        let (outcome, context) = try await style(demo, makeRequest(pieceMode: .onlyMine))
        let result = try #require(outcome.result)
        #expect(result.versions.allSatisfy { $0.ideas.isEmpty })
        #expect(ResultCheck.problems(in: result, for: context).isEmpty)
    }

    @Test func aSuitcaseStaysOwnedOnlyAndSaysWhy() async throws {
        // LR-05b.2: Jose's house, with Mine + one idea.
        let (outcome, context) = try await style(demo, makeRequest(source: .suitcase(DemoCloset.josesHouse)))
        let result = try #require(outcome.result)
        #expect(result.versions.allSatisfy { $0.ideas.isEmpty })
        #expect(result.notes.contains(.noNewPieceInSuitcase))
        #expect(ResultCheck.problems(in: result, for: context).isEmpty)
        let members = try #require(demo.suitcases.first { $0.id == DemoCloset.josesHouse }).garmentIDs
        #expect(result.versions.allSatisfy { Set($0.garmentIDs).isSubset(of: members) })
    }

    @Test func aSmallSuitcaseGivesAPartialResult() async throws {
        // Jose's house has no dressier piece to swap in, so Dressed up is missing.
        let (outcome, _) = try await style(demo, makeRequest(source: .suitcase(DemoCloset.josesHouse)))
        guard case .partial(let result, let missing) = outcome else {
            Issue.record("Expected a partial result, got \(outcome)")
            return
        }
        #expect(missing == [MissingVersion(version: .dressedUp, reason: .noDressierPiece)])
        #expect(result.versions.map(\.version) == [.simple, .somethingNew])
    }

    @Test func aSuitcaseWithoutBottomsIsInsufficient() async throws {
        let (outcome, _) = try await style(demo, makeRequest(source: .suitcase(DemoCloset.gym)))
        #expect(outcome == .insufficient(InsufficientWardrobe(source: .suitcase(DemoCloset.gym), missing: [.bottom])))
    }

    @Test func anEmptyClosetIsInsufficientNotAFailure() async throws {
        let empty = FixtureSet.empty.data(now: TestTime.now, calendar: TestTime.calendar)
        let (outcome, _) = try await style(empty, makeRequest())
        #expect(outcome == .insufficient(InsufficientWardrobe(source: .mainCloset, missing: [.top, .bottom, .shoes])))
    }

    @Test func theStartingPieceIsInEveryVersion() async throws {
        let (outcome, context) = try await style(demo, makeRequest(occasion: .casual, startingPieceID: "g-wide-jeans"))
        let result = try #require(outcome.result)
        #expect(result.versions.allSatisfy { $0.garmentIDs.contains("g-wide-jeans") })
        #expect(ResultCheck.problems(in: result, for: context).isEmpty)
    }

    @Test func aStartingDressIsTheMainPiece() async throws {
        var data = demo
        if let index = data.garments.firstIndex(where: { $0.id == "g-blue-dress" }) {
            data.garments[index].availability = .available
        }
        let (outcome, _) = try await style(data, makeRequest(occasion: .dateNight, startingPieceID: "g-blue-dress"))
        let simple = try #require(outcome.result?.simple)
        #expect(simple.garmentIDs.contains("g-blue-dress"))
        let categories = Dictionary(uniqueKeysWithValues: data.garments.map { ($0.id, $0.category) })
        #expect(!simple.garmentIDs.contains { [.top, .bottom].contains(categories[$0]) })
    }

    @Test func trackingLaundrySkipsDirtyPieces() async throws {
        // RD-11.2 in reverse: with tracking on, a dirty piece is never used.
        let (outcome, _) = try await style(demo, makeRequest(occasion: .dateNight, tracksLaundry: true))
        let used = Set(outcome.result?.versions.flatMap(\.garmentIDs) ?? [])
        #expect(!used.contains("g-lace-top"))
        #expect(!used.contains("g-black-tee"))
    }

    @Test func rainAddsALayerAndIndoorsDoesNot() async throws {
        let (rain, _) = try await style(demo, makeRequest(weatherChoice: .useToday))
        let (indoors, _) = try await style(demo, makeRequest(weatherChoice: .indoors))
        let layers: Set<Garment.ID> = ["g-navy-cardigan", "g-brown-jacket"]
        #expect(rain.result?.simple?.garmentIDs.contains { layers.contains($0) } == true)
        #expect(indoors.result?.simple?.garmentIDs.contains { layers.contains($0) } == false)
    }

    @Test func alternatesAreOwnedEligibleAndNotInTheLook() async throws {
        let (outcome, context) = try await style(demo, makeRequest())
        let result = try #require(outcome.result)
        let eligible = Set(context.eligibleGarments.map(\.id))
        let inLook = Set(result.simple?.garmentIDs ?? [])
        for alternates in result.alternates {
            #expect(alternates.garmentIDs.allSatisfy { eligible.contains($0) && !inLook.contains($0) })
        }
    }

    // MARK: Repeat window (LR-10.2, LR-10.3)

    private var repeatCloset: Closet {
        Closet(garments: [
            garment("top-a", .top, occasions: [.office]),
            garment("top-b", .top, occasions: []),
            garment("bottom", .bottom, occasions: [.office]),
            garment("shoes", .shoes, occasions: [.office]),
        ])
    }

    private func mainPieces(_ outcome: StyleOutcome) -> Set<Garment.ID> {
        Set(outcome.result?.simple?.garmentIDs ?? []).subtracting(["shoes"])
    }

    @Test func skipsALookWornFiveDaysAgo() async throws {
        var closet = repeatCloset
        closet.looks = [wornLook(id: "o-worn", pieces: ["top-a", "bottom", "shoes"], wornDaysAgo: 5)]
        let (outcome, _) = try await style(closet, makeRequest())
        #expect(mainPieces(outcome) == ["top-b", "bottom"])
        #expect(outcome.result?.notes.contains { if case .wornRecently = $0 { true } else { false } } == false)
    }

    @Test func offersItAgainOutsideTheWindowOrWithIDontMind() async throws {
        var closet = repeatCloset
        closet.looks = [wornLook(id: "o-worn", pieces: ["top-a", "bottom", "shoes"], wornDaysAgo: 8)]
        let (afterAWeek, _) = try await style(closet, makeRequest())
        #expect(mainPieces(afterAWeek) == ["top-a", "bottom"])

        closet.looks = [wornLook(id: "o-worn", pieces: ["top-a", "bottom", "shoes"], wornDaysAgo: 2)]
        let (dontMind, _) = try await style(closet, makeRequest(repeatWindow: .noLimit))
        #expect(mainPieces(dontMind) == ["top-a", "bottom"])
    }

    @Test func notesARepeatWhenNothingElseFits() async throws {
        var closet = repeatCloset
        closet.garments.removeAll { $0.id == "top-b" }
        closet.looks = [wornLook(id: "o-worn", pieces: ["top-a", "bottom", "shoes"], wornDaysAgo: 3)]
        let (outcome, _) = try await style(closet, makeRequest())
        #expect(mainPieces(outcome) == ["top-a", "bottom"])
        #expect(outcome.result?.notes.contains(.wornRecently(lastWorn: TestTime.day(-3))) == true)
    }

    // MARK: Try a different outfit (Phase 10b)

    /// LR-05a.4: with the first base marked as shown, the next result starts from another one.
    @Test func aShownBaseGivesADifferentOutfit() async throws {
        let first = try StylingContext.from(demo, request: makeRequest())
        let firstOutcome = try await MockStylist().style(first)
        let firstMain = mainPieces(of: firstOutcome, in: demo)
        var again = try StylingContext.from(demo, request: makeRequest("req-2"))
        again.shownCombinations = [firstMain]
        let secondOutcome = try await MockStylist().style(again)
        let secondMain = mainPieces(of: secondOutcome, in: demo)
        #expect(!secondMain.isEmpty)
        #expect(secondMain != firstMain)
        #expect(secondOutcome.result?.notes.contains(.noOtherOutfit) == false)
        if let result = secondOutcome.result {
            #expect(ResultCheck.problems(in: result, for: again).isEmpty)
        }
    }

    /// A required colour nothing usable has is said, not invented (PRD §8.3).
    @Test func anUnmetRequiredColourIsNoted() async throws {
        var request = makeRequest()
        request.color = ColorWish(.purple, strength: .required)
        let (outcome, _) = try await style(demo, request)
        #expect(outcome.result?.notes.contains(.requiredColorNotMet(.purple)) == true)
        request.color = ColorWish(.purple)
        let (preferred, _) = try await style(demo, request)
        #expect(preferred.result?.notes.contains(.requiredColorNotMet(.purple)) == false)
    }

    /// When every base has been shown, the best one comes round again and the result says so.
    @Test func noOtherBaseComesRoundAgainWithANote() async throws {
        var context = try StylingContext.from(repeatCloset, request: makeRequest())
        context.shownCombinations = [["top-a", "bottom"], ["top-b", "bottom"]]
        let outcome = try await MockStylist().style(context)
        #expect(mainPieces(outcome) == ["top-a", "bottom"])
        #expect(outcome.result?.notes.contains(.noOtherOutfit) == true)
    }

    private func mainPieces(of outcome: StyleOutcome, in data: some FixtureDataLike) -> Set<Garment.ID> {
        let categories = Dictionary(data.garments.map { ($0.id, $0.category) }, uniquingKeysWith: { first, _ in first })
        guard let simple = outcome.result?.simple else { return [] }
        return WearRules.mainPieces(of: simple, categories: categories)
    }

    // MARK: Failure modes

    @Test func aFailingStylistThrows() async throws {
        let context = try StylingContext.from(demo, request: makeRequest())
        await #expect(throws: StylistError.notCompleted) {
            try await MockStylist(mode: .failing(.notCompleted)).style(context)
        }
        await #expect(throws: StylistError.offline) { try await MockStylist(mode: .failing(.offline)).style(context) }
    }

    @Test func thePartialModeDropsSomethingNew() async throws {
        let (outcome, context) = try await style(demo, makeRequest(), stylist: MockStylist(mode: .partial))
        guard case .partial(let result, let missing) = outcome else {
            Issue.record("Expected a partial result, got \(outcome)")
            return
        }
        #expect(result.versions.map(\.version) == [.simple, .dressedUp])
        #expect(missing.map(\.version) == [.somethingNew])
        #expect(ResultCheck.problems(in: result, for: context).isEmpty)
    }

    @Test func theInsufficientModeSaysWhatIsMissing() async throws {
        let (outcome, _) = try await style(demo, makeRequest(), stylist: MockStylist(mode: .insufficient))
        #expect(outcome == .insufficient(InsufficientWardrobe(source: .mainCloset, missing: [.bottom, .shoes])))
    }

    /// `offline-once`: the first request fails as offline, the retry works.
    @Test func failingOnceWorksTheSecondTime() async throws {
        let context = try StylingContext.from(demo, request: makeRequest())
        let stylist = MockStylist(mode: .failingOnce(.offline))
        await #expect(throws: StylistError.offline) { try await stylist.style(context) }
        let outcome = try await stylist.style(context)
        #expect(outcome.result?.versions.count == 3)
    }

    @Test func aSlowStylistCanBeCancelled() async throws {
        let context = try StylingContext.from(demo, request: makeRequest())
        let task = Task { try await MockStylist(latency: .seconds(30)).style(context) }
        task.cancel()
        await #expect(throws: StylistError.cancelled) { try await task.value }
    }

    @Test func fixtureServicesWireEachBehavior() async throws {
        let offline = FixtureServices.make(
            set: .demo, behavior: .offline, now: TestTime.now, calendar: TestTime.calendar)
        await #expect(throws: WeatherError.unavailable) { try await offline.weather.currentWeather() }
        #expect(try await offline.closet.garments().count == 21)  // local data still works offline

        let failing = FixtureServices.make(
            set: .demo, behavior: .storesFail, now: TestTime.now, calendar: TestTime.calendar)
        await #expect(throws: StoreError.unavailable) { try await failing.looks.looks() }

        let normal = FixtureServices.make(set: .empty, now: TestTime.now, calendar: TestTime.calendar)
        #expect(try await normal.weather.currentWeather().condition == .rain)
        #expect(try await normal.images.imageData(for: .sample("x"), maxPixelSize: 100) == nil)
    }
}

/// A worn look for the repeat-window tests.
private func wornLook(id: Look.ID, pieces: [Garment.ID], wornDaysAgo: Int) -> Look {
    Look(
        id: id,
        version: .simple,
        pieces: pieces.map { LookPiece(id: LookPiece.ID("\(id)-\($0)"), content: .garment($0), isSameAsSimple: true) },
        isSaved: true,
        wornOn: [TestTime.day(-wornDaysAgo)],
        createdAt: TestTime.day(-30)
    )
}
