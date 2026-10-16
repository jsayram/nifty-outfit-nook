import Foundation
import Models
import NookTestSupport
import Testing

struct ResultCheckTests {
    private let garments = [
        Make.garment("top", .top),
        Make.garment("top2", .top, dressiness: .dressy),
        Make.garment("bottom", .bottom),
        Make.garment("shoes", .shoes),
        Make.garment("shoes2", .shoes),
    ]
    private let idea = PieceIdea(name: "Cropped cardigan", category: .layer)

    private func context(_ request: StyleRequest = Make.request()) -> StylingContext {
        StylingContext(request: request, eligibleGarments: garments, now: TestTime.now, calendar: TestTime.calendar)
    }

    private func result(_ versions: [Look]) -> StyleResult {
        StyleResult(id: "r-1", requestID: "req-1", versions: versions, createdAt: TestTime.now)
    }

    private var simple: Look { Make.look("simple", version: .simple, garments: ["top", "bottom", "shoes"]) }
    private var dressedUp: Look {
        Make.look(
            "dressed", version: .dressedUp, garments: ["top2", "bottom", "shoes"], sameAsSimple: ["bottom", "shoes"])
    }
    private var somethingNew: Look {
        Make.look("new", version: .somethingNew, garments: ["top", "bottom", "shoes"], idea: idea)
    }

    @Test func aGoodResultHasNoProblems() {
        #expect(ResultCheck.problems(in: result([simple, dressedUp, somethingNew]), for: context()).isEmpty)
    }

    @Test func simpleIsRequired() {
        #expect(ResultCheck.problems(in: result([dressedUp]), for: context()) == [.noSimpleVersion])
    }

    @Test func noIdeaWithOnlyMine() {
        let problems = ResultCheck.problems(
            in: result([simple, somethingNew]), for: context(Make.request(pieceMode: .onlyMine)))
        #expect(problems == [.ideaNotAllowed(.somethingNew)])  // LR-05b.2
    }

    @Test func noIdeaInASuitcase() {
        let request = Make.request(source: .suitcase("s-1"))
        #expect(
            ResultCheck.problems(in: result([simple, somethingNew]), for: context(request)) == [
                .ideaNotAllowed(.somethingNew)
            ])
    }

    @Test func ideasOnlyInSomethingNewAndOnlyOne() {
        var twoIdeas = somethingNew
        twoIdeas.pieces.append(LookPiece(id: "extra", content: .idea(idea)))
        let ideaInDressedUp = Make.look(
            "dressed",
            version: .dressedUp,
            garments: ["top", "bottom", "shoes"],
            idea: idea
        )
        let problems = ResultCheck.problems(in: result([simple, ideaInDressedUp, twoIdeas]), for: context())
        #expect(problems.contains(.ideaNotAllowed(.dressedUp)))
        #expect(problems.contains(.moreThanOneIdea(.somethingNew)))
    }

    @Test func everyOwnedPieceMustBeEligible() {
        let withWishlist = Make.look("simple", garments: ["top", "bottom", "wishlist-coat"])
        #expect(
            ResultCheck.problems(in: result([withWishlist]), for: context()) == [
                .notEligible("wishlist-coat", .simple)
            ])
    }

    @Test func theStartingPieceIsInEveryVersion() {
        let request = Make.request(startingPieceID: "top")
        #expect(
            ResultCheck.problems(in: result([simple, dressedUp]), for: context(request)) == [
                .missingStartingPiece(.dressedUp)
            ])
    }

    @Test func otherVersionsKeepSomethingFromSimple() {
        let unrelated = Make.look("dressed", version: .dressedUp, garments: ["top2", "shoes2"], sameAsSimple: [])
        #expect(
            ResultCheck.problems(in: result([simple, unrelated]), for: context()) == [
                .sharesNothingWithSimple(.dressedUp)
            ])
    }

    @Test func sameAsSimpleMarksMustBeTrue() {
        let wrongMarks = Make.look("dressed", version: .dressedUp, garments: ["top2", "bottom", "shoes"])
        #expect(
            ResultCheck.problems(in: result([simple, wrongMarks]), for: context()) == [
                .wrongSameAsSimpleMark(.dressedUp)
            ])
    }

    @Test func looksHaveTwoToSixPiecesAndNoRepeats() {
        let tiny = Make.look("simple", garments: ["top"])
        #expect(ResultCheck.problems(in: result([tiny]), for: context()) == [.pieceCount(.simple)])
        let twice = Make.look("simple", garments: ["top", "top", "shoes"])
        #expect(ResultCheck.problems(in: result([twice]), for: context()) == [.repeatedPiece("top", .simple)])
    }

    @Test func eachVersionAppearsOnce() {
        #expect(ResultCheck.problems(in: result([simple, simple]), for: context()) == [.repeatedVersion(.simple)])
    }
}
