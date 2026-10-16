import Foundation
import Models
import NookTestSupport
import Testing

struct LookRulesTests {
    @Test func aDressOrATopAndABottomMakeALook() {
        #expect(LookRules.hasMainPieces([.dress, .shoes]))
        #expect(LookRules.hasMainPieces([.top, .bottom]))
        #expect(!LookRules.hasMainPieces([.top, .shoes, .layer]))
        #expect(!LookRules.hasMainPieces([.bottom, .shoes]))
    }

    @Test func shapeProblems() {
        #expect(LookRules.shapeProblems(of: [.top, .bottom, .shoes], onePerKind: true).isEmpty)
        #expect(LookRules.shapeProblems(of: [.dress], onePerKind: true) == [.tooFewPieces])
        #expect(LookRules.shapeProblems(of: [], onePerKind: true) == [.tooFewPieces, .needsMainPieces])
        #expect(LookRules.shapeProblems(of: [.top, .shoes], onePerKind: true) == [.needsMainPieces])
        let seven: [GarmentCategory] = [.layer, .top, .bottom, .dress, .shoes, .bag, .accessory]
        #expect(LookRules.shapeProblems(of: seven, onePerKind: true) == [.tooManyPieces])
        #expect(
            LookRules.shapeProblems(of: [.top, .top, .bottom], onePerKind: true) == [.twoOfAKind(.top)])
        // A stylist's look changed in Swap isn't held to one of each kind.
        #expect(LookRules.shapeProblems(of: [.top, .top, .bottom], onePerKind: false).isEmpty)
    }

    @Test func piecesThatCantBeWornAreProblems() {
        let garments = [
            Make.garment("top", .top),
            Make.garment("bottom", .bottom, laundry: .dirty),
            Make.garment("shoes", .shoes, ownership: .wishlisted),
        ]
        let tracking = LookRules.problems(
            building: garments, members: nil, tracksLaundry: true, on: TestTime.now)
        #expect(tracking == [.notUsable("bottom", [.dirty]), .notUsable("shoes", [.notOwned])])
        let notTracking = LookRules.problems(
            building: garments, members: nil, tracksLaundry: false, on: TestTime.now)
        #expect(notTracking == [.notUsable("shoes", [.notOwned])])
        let inSuitcase = LookRules.problems(
            building: Array(garments.prefix(2)), members: ["top"], tracksLaundry: false, on: TestTime.now)
        #expect(inSuitcase == [.notUsable("bottom", [.outsideSource])])
    }
}
