import Foundation
import Models
import NookTestSupport
import Testing

/// Possible matches (PRD §7.6): pieces with some of the typed words, when none has them all.
struct PossibleMatchesTests {
    private let garments: [Garment] = {
        var shirt = Make.garment("g-shirt", .top, colors: [.pink])
        shirt.name = "Pink shirt"
        var blouse = Make.garment("g-blouse", .top, colors: [.white])
        blouse.name = "White lace blouse"
        blouse.otherNames = ["Party top"]
        var skirt = Make.garment("g-skirt", .bottom, colors: [.pink])
        skirt.name = "Pink pleated skirt"
        var dirty = Make.garment("g-dirty", .top, colors: [.pink])
        dirty.name = "Pink tee"
        dirty.laundry = .dirty
        return [shirt, blouse, skirt, dirty]
    }()

    private let suitcases = [
        Suitcase(id: "s-weekend", name: "Weekend", garmentIDs: ["g-skirt", "g-blouse"], createdAt: TestTime.now)
    ]

    private func possible(_ filter: GarmentFilter, filler: Set<String> = ["my", "the"]) -> [PossibleMatch] {
        filter.possibleMatches(in: garments, suitcases: suitcases, fillerWords: filler)
    }

    @Test func piecesWithSomeWordsSayWhichAreMissing() {
        let matches = possible(GarmentFilter(query: "cute pink shirt"))
        #expect(matches.map(\.garment.id) == ["g-shirt", "g-skirt", "g-dirty"])
        #expect(matches[0].matchedWords == ["pink", "shirt"])
        #expect(matches[0].missingWords == ["cute"])
        #expect(matches[1].matchedWords == ["pink"])
        #expect(matches[1].missingWords == ["cute", "shirt"])
    }

    @Test func moreWordsComeFirstThenTheOrderGiven() {
        let matches = possible(GarmentFilter(query: "white pink party"))
        // The blouse has white and party (an other name); the pink pieces have one word each.
        #expect(matches.map(\.garment.id) == ["g-blouse", "g-shirt", "g-skirt", "g-dirty"])
    }

    @Test func chipsAndFiltersStillApplyInFull() {
        #expect(possible(GarmentFilter(categories: [.bottom], query: "cute pink")).map(\.garment.id) == ["g-skirt"])
        #expect(possible(GarmentFilter(laundry: .dirty, query: "cute pink")).map(\.garment.id) == ["g-dirty"])
        #expect(
            possible(GarmentFilter(packing: .suitcase("s-weekend"), query: "pink lace")).map(\.garment.id)
                == ["g-blouse", "g-skirt"])
    }

    @Test func aPieceWithEveryWordIsntAPossibleMatch() {
        // Every typed word on the skirt: it's a real result, so it isn't listed here.
        #expect(!possible(GarmentFilter(query: "pink skirt")).map(\.garment.id).contains("g-skirt"))
    }

    @Test func fillerWordsDontCountEitherWay() {
        let matches = possible(GarmentFilter(query: "my pink thing"))
        #expect(matches.first?.missingWords == ["thing"])
        #expect(matches.first?.matchedWords == ["pink"])
        // Filler is compared ignoring case and accents.
        #expect(GarmentFilter(query: "MY Pink pink the").contentWords(ignoring: ["my", "the"]) == ["Pink"])
    }

    @Test func oneWordHasNothingToLoosen() {
        #expect(possible(GarmentFilter(query: "cute")).isEmpty)
        #expect(possible(GarmentFilter(query: "the cute")).isEmpty)
        #expect(possible(GarmentFilter()).isEmpty)
    }

    @Test func noWordMatchedMeansNoPossibleMatch() {
        #expect(possible(GarmentFilter(query: "velvet cape")).isEmpty)
    }

    @Test func theListIsBounded() {
        let many = (0..<20).map { index in
            var garment = Make.garment(Garment.ID("g-\(index)"), .top, colors: [.pink])
            garment.name = "Pink top \(index)"
            return garment
        }
        let matches = GarmentFilter(query: "pink velvet").possibleMatches(in: many, suitcases: [])
        #expect(matches.count == GarmentFilter.possibleMatchesMaximum)
        #expect(matches.first?.garment.id == "g-0")
    }

    @Test func extraWordsCount() {
        let matches = GarmentFilter(query: "cute blouse").possibleMatches(
            in: garments, suitcases: [], extraWords: { $0.category == .bottom ? ["Bottoms"] : [] })
        #expect(matches.map(\.garment.id) == ["g-blouse"])
        let bottoms = GarmentFilter(query: "cute bottoms").possibleMatches(
            in: garments, suitcases: [], extraWords: { $0.category == .bottom ? ["Bottoms"] : [] })
        #expect(bottoms.map(\.garment.id) == ["g-skirt"])
    }
}
