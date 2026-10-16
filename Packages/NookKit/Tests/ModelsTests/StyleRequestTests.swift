import Foundation
import Models
import NookTestSupport
import Testing

struct StyleRequestTests {
    @Test(arguments: [
        (PieceMode.mineAndOneIdea, WardrobeSource.mainCloset, true),
        (.onlyMine, .mainCloset, false),
        (.mineAndOneIdea, .suitcase("s-1"), false),
        (.onlyMine, .suitcase("s-1"), false),
    ])
    func newPieceIdeasOnlyWithMineAndOneIdeaInTheMainCloset(mode: PieceMode, source: WardrobeSource, allowed: Bool) {
        // LR-03.4, LR-05b.1 and LR-05b.2: a suitcase stays owned-only whatever Preferences says.
        #expect(Make.request(source: source, pieceMode: mode).allowsNewPieceIdea == allowed)
    }

    @Test func weatherShapesTheLookOnlyWhenUsingToday() {
        var request = Make.request()
        let weather = WeatherSnapshot(condition: .rain, temperatureCelsius: 14, observedAt: TestTime.now)
        request.weather = weather
        #expect(request.weatherToUse == weather)
        request.weatherChoice = .indoors
        #expect(request.weatherToUse == nil)
        request.weatherChoice = .ignore
        #expect(request.weatherToUse == nil)
    }

    @Test(arguments: [(-5.0, TemperatureBand.cold), (9.9, .cold), (10, .cool), (17.9, .cool), (18, .mild), (26, .hot)])
    func temperatureBands(celsius: Double, band: TemperatureBand) {
        #expect(WeatherSnapshot(condition: .sun, temperatureCelsius: celsius, observedAt: TestTime.now).band == band)
    }

    @Test func aRequestSurvivesEncoding() throws {
        var request = Make.request(source: .suitcase("s-1"), startingPieceID: "g-1")
        request.comfort = .fitted
        request.color = ColorWish(.navy, strength: .required, scope: .shoes)
        request.occasion = .other
        request.occasionNote = "Museum visit"
        request.weather = WeatherSnapshot(
            condition: .snow, temperatureCelsius: -2, isNight: true, observedAt: TestTime.now)
        #expect(try JSONDecoder().decode(StyleRequest.self, from: JSONEncoder().encode(request)) == request)
    }

    /// LR-05a.4: Try a different outfit is a new request with the same choices.
    @Test func againKeepsEveryChoiceWithANewID() {
        var request = Make.request(source: .suitcase("s-1"), startingPieceID: "g-1")
        request.comfort = .fitted
        request.color = ColorWish(.navy, strength: .required, scope: .shoes)
        request.occasion = .other
        request.occasionNote = "Museum visit"
        request.weatherChoice = .indoors
        let later = TestTime.day(1)
        let again = request.again(id: "req-2", createdAt: later)
        #expect(again.id == "req-2")
        #expect(again.createdAt == later)
        let expected = StyleRequest(
            id: request.id, source: again.source, occasion: again.occasion, occasionNote: again.occasionNote,
            weatherChoice: again.weatherChoice, weather: again.weather, comfort: again.comfort, color: again.color,
            preferences: again.preferences, startingPieceID: again.startingPieceID, createdAt: request.createdAt)
        #expect(expected == request)
    }
}

struct StylingContextTests {
    private let garments = [
        Make.garment("g-top", .top),
        Make.garment("g-bottom", .bottom),
        Make.garment("g-shoes", .shoes),
        Make.garment("g-wish", .top, ownership: .wishlisted),
        Make.garment("g-dirty", .top, laundry: .dirty),
    ]
    private let suitcases = [
        Suitcase(id: "s-1", name: "Weekend", garmentIDs: ["g-top", "g-shoes"], createdAt: TestTime.now),
        Suitcase(id: "s-old", name: "Old", garmentIDs: ["g-top"], isArchived: true, createdAt: TestTime.now),
    ]

    private func make(_ request: StyleRequest, looks: [Look] = []) throws(StylingContextError) -> StylingContext {
        try StylingContext.make(
            request: request,
            garments: garments,
            suitcases: suitcases,
            looks: looks,
            usualFit: .relaxed,
            now: TestTime.now,
            calendar: TestTime.calendar
        )
    }

    @Test func mainClosetUsesEveryEligiblePieceInIDOrder() throws {
        let context = try make(Make.request())
        #expect(context.eligibleGarments.map(\.id) == ["g-bottom", "g-dirty", "g-shoes", "g-top"])
    }

    @Test func carriesTheBasesAlreadyShown() throws {
        let shown: Set<Set<Garment.ID>> = [["g-top", "g-bottom"]]
        let context = try StylingContext.make(
            request: Make.request(), garments: garments, suitcases: suitcases, looks: [], usualFit: nil,
            shown: shown, now: TestTime.now, calendar: TestTime.calendar)
        #expect(context.shownCombinations == shown)
        #expect(try make(Make.request()).shownCombinations.isEmpty)
    }

    @Test func trackingLaundryDropsDirtyPieces() throws {
        let context = try make(Make.request(tracksLaundry: true))
        #expect(!context.eligibleGarments.map(\.id).contains("g-dirty"))
    }

    @Test func aSuitcaseLimitsThePieces() throws {
        let context = try make(Make.request(source: .suitcase("s-1")))
        #expect(context.eligibleGarments.map(\.id) == ["g-shoes", "g-top"])
    }

    @Test func aMissingOrArchivedSuitcaseIsAnError() {
        #expect(throws: StylingContextError.suitcaseNotFound) { try make(Make.request(source: .suitcase("s-x"))) }
        #expect(throws: StylingContextError.suitcaseArchived) { try make(Make.request(source: .suitcase("s-old"))) }
    }

    @Test func theStartingPieceMustBeUsable() {
        #expect(throws: StylingContextError.startingPieceNotFound) { try make(Make.request(startingPieceID: "g-x")) }
        #expect(throws: StylingContextError.startingPieceNotEligible([.notOwned])) {
            try make(Make.request(startingPieceID: "g-wish"))
        }
        #expect(throws: StylingContextError.startingPieceNotEligible([.outsideSource])) {
            try make(Make.request(source: .suitcase("s-1"), startingPieceID: "g-bottom"))
        }
    }

    @Test func todaysComfortWinsOverTheUsualFit() throws {
        var context = try make(Make.request())
        #expect(context.effectiveComfort == .relaxed)
        context.request.comfort = .fitted
        #expect(context.effectiveComfort == .fitted)
    }

    @Test func carriesRecentlyWornCombinations() throws {
        let worn = Make.look("o-1", garments: ["g-top", "g-bottom", "g-shoes"], wornOn: [TestTime.day(-2)])
        let context = try make(Make.request(), looks: [worn])
        #expect(context.recentCombinations == [["g-top", "g-bottom"]: TestTime.day(-2)])
        let relaxed = try make(Make.request(repeatWindow: .noLimit), looks: [worn])
        #expect(relaxed.recentCombinations.isEmpty)
    }
}
