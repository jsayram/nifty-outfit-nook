import Foundation
import NookTestSupport
import Testing

@testable import Models

/// Phase 27a on the phone: what a styling request may carry, how the stylist's answer becomes
/// looks, and "From your history" (FR-58) before a paid request.
struct CloudStylingTests {
    static let pieces = [
        Make.garment("g-top", .top, colors: [.cream]),
        Make.garment("g-top2", .top, colors: [.white], dressiness: .casual),
        Make.garment("g-bottom", .bottom, colors: [.olive]),
        Make.garment("g-shoes", .shoes, colors: [.brown]),
        Make.garment("g-layer", .layer, colors: [.navy], dressiness: .dressy),
    ]

    static func context(
        _ request: StyleRequest = Make.request(), recent: [Set<Garment.ID>: Date] = [:],
        shown: Set<Set<Garment.ID>> = [], pieces: [Garment] = pieces
    ) -> StylingContext {
        StylingContext(
            request: request, eligibleGarments: pieces, recentCombinations: recent, shownCombinations: shown,
            now: TestTime.now, calendar: TestTime.calendar)
    }

    static func rainy(_ request: StyleRequest) -> StyleRequest {
        var request = request
        request.weather = WeatherSnapshot(condition: .rain, temperatureCelsius: 14, observedAt: TestTime.now)
        return request
    }

    // MARK: The request

    @Test func theCallCarriesTheChoicesAndOnlyTheWeatherSummary() {
        var request = Self.rainy(Make.request(startingPieceID: "g-top"))
        request.color = ColorWish(.olive, strength: .required)
        let recent: [Set<Garment.ID>: Date] = [["g-top2", "g-bottom"]: TestTime.day(-2)]
        let call = StyleCall.outfit(
            from: Self.context(request, recent: recent, shown: [["g-top", "g-bottom"]]), consentVersion: "stylist-1")
        #expect(call.mode == .full)
        #expect(call.pieces.map(\.id) == Self.pieces.map(\.id).sorted())
        let outfit = try! #require(call.outfit)
        #expect(outfit.weather == request.weather?.summary)
        #expect(outfit.startingPieceID == "g-top")
        #expect(outfit.ideaAllowed)
        #expect(Set(outfit.avoid.map(Set.init)) == [["g-top2", "g-bottom"], ["g-top", "g-bottom"]])
        #expect(call.contextRevision.hasPrefix("rev_"))
        // Indoors or ignoring the weather sends none.
        request.weatherChoice = .indoors
        #expect(StyleCall.outfit(from: Self.context(request), consentVersion: "stylist-1").outfit?.weather == nil)
    }

    @Test func aLargeClosetIsBoundedAndKeepsTheStartingPiece() {
        let many = (0..<200).map { Make.garment(.init("g-\(String(format: "%03d", $0))"), .top) }
        let call = StyleCall.outfit(
            from: Self.context(Make.request(startingPieceID: "g-000"), pieces: many), consentVersion: "stylist-1")
        #expect(call.pieces.count == StyleCall.maximumPieces)
        #expect(call.pieces.contains { $0.id == "g-000" })
    }

    // MARK: The answer

    @Test func anAnswerBecomesLooksWithWhyLinesMarksAndIntent() throws {
        let request = Self.rainy(Make.request())
        let answer = StyleAnswer.looks(
            [
                .init(version: .simple, pieces: ["g-shoes", "g-bottom", "g-top"], why: "Easy for the office."),
                .init(version: .dressedUp, pieces: ["g-top", "g-bottom", "g-shoes", "g-layer"], why: ""),
                .init(
                    version: .somethingNew, pieces: ["g-top", "g-bottom", "g-shoes"],
                    idea: PieceIdea(name: "Rust vest", category: .layer, colors: [.orange]), why: "A vest adds texture."
                ),
            ], missing: [], fromCache: true)
        let outcome = try CloudStylist.outcome(
            answer, for: Self.context(request), sentIDs: Set(Self.pieces.map(\.id)))
        guard case .complete(let result) = outcome else {
            Issue.record("Expected complete, got \(outcome)")
            return
        }
        #expect(ResultCheck.problems(in: result, for: Self.context(request)).isEmpty)
        let simple = try #require(result.simple)
        #expect(simple.garmentIDs == ["g-top", "g-bottom", "g-shoes"], "drawn in category order")
        #expect(simple.why == "Easy for the office.")
        #expect(result.look(for: .dressedUp)?.why == nil, "an empty why line isn't kept")
        #expect(simple.intent == StyleIntent(request))
        #expect(result.notes.contains(.answeredAgain))
    }

    @Test func anAnswerNamingAPieceThatWasNotSentIsNotShown() {
        let answer = StyleAnswer.looks(
            [.init(version: .simple, pieces: ["g-top", "g-not-hers"], why: "x")], missing: [], fromCache: false)
        #expect(throws: StylistError.notCompleted) {
            try CloudStylist.outcome(answer, for: Self.context(), sentIDs: Set(Self.pieces.map(\.id)))
        }
    }

    @Test func insufficientAndLimitsKeepTheirMeaning() throws {
        let outcome = try CloudStylist.outcome(
            .insufficient([.bottom], fromCache: false), for: Self.context(), sentIDs: [])
        #expect(outcome == .insufficient(InsufficientWardrobe(source: .mainCloset, missing: [.bottom])))
        #expect(CloudStylist.error(for: .didNotFinish(retryAfterSeconds: 30)) == .notCompleted)
        #expect(CloudStylist.error(for: .account(.offline)) == .offline)
        #expect(CloudStylist.error(for: .needsConsent) == .needsConsent)
        #expect(
            CloudStylist.error(for: .rateLimited(retryAfterSeconds: 4)) == .limited(.rateLimited(retryAfterSeconds: 4)))
    }

    // MARK: From your history

    static func earlier(_ request: StyleRequest, garments: [Garment.ID], result: StyleResult.ID = "r-old") -> Look {
        var look = Make.look(.init("\(result)-simple"), garments: garments)
        look.resultID = result
        look.intent = StyleIntent(request)
        return look
    }

    @Test func anEarlierResultForTheSameRequestIsFoundIfItsPiecesCanStillBeWorn() throws {
        let request = Self.rainy(Make.request())
        let old = Self.earlier(request, garments: ["g-top", "g-bottom", "g-shoes"])
        let match = try #require(StyleHistory.match(for: Self.context(request), in: [old]))
        #expect(match.notes == [.fromHistory])
        #expect(match.simple?.id == old.id, "the same look, so saving it saves that one")

        // A piece that's away today, another occasion, or a main combination already shown: no.
        let fewer = Self.pieces.filter { $0.id != "g-shoes" }
        #expect(StyleHistory.match(for: Self.context(request, pieces: fewer), in: [old]) == nil)
        var brunch = request
        brunch.occasion = .brunch
        #expect(StyleHistory.match(for: Self.context(brunch), in: [old]) == nil)
        #expect(StyleHistory.match(for: Self.context(request, shown: [["g-top", "g-bottom"]]), in: [old]) == nil)
    }

    @Test func freeTextTodaysComfortOrUnreadWeatherNeverMakeAnExactMatch() {
        var request = Self.rainy(Make.request())
        let old = Self.earlier(request, garments: ["g-top", "g-bottom", "g-shoes"])
        request.comfort = .relaxed
        #expect(StyleIntent(request) == nil)
        #expect(StyleHistory.match(for: Self.context(request), in: [old]) == nil)
        var other = Self.rainy(Make.request(occasion: .other))
        other.occasionNote = "museum"
        #expect(StyleIntent(other) == nil)
        var unread = Make.request()
        unread.weather = nil
        #expect(StyleIntent(unread) == nil)
        // A mild dry day is a different request from a cool wet one.
        var mild = Make.request()
        mild.weather = WeatherSnapshot(condition: .sun, temperatureCelsius: 22, observedAt: TestTime.now)
        #expect(StyleIntent(mild) != StyleIntent(Self.rainy(Make.request())))
    }

    @Test func theNewestMatchingResultWins() throws {
        let request = Self.rainy(Make.request())
        var older = Self.earlier(request, garments: ["g-top", "g-bottom", "g-shoes"], result: "r-1")
        older.createdAt = TestTime.day(-3)
        let newer = Self.earlier(request, garments: ["g-top2", "g-bottom", "g-shoes"], result: "r-2")
        let match = try #require(StyleHistory.match(for: Self.context(request), in: [older, newer]))
        #expect(match.id == "r-2")
    }
}
