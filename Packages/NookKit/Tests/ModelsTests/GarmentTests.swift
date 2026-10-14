import Foundation
import Models
import Testing

struct GarmentTests {
    @Test func entityIDsEncodeAsBareStrings() throws {
        let data = try JSONEncoder().encode([Garment.ID("g-1")])
        #expect(String(decoding: data, as: UTF8.self) == #"["g-1"]"#)
        #expect(try JSONDecoder().decode([Garment.ID].self, from: data) == ["g-1"])
    }

    @Test func randomIDsDiffer() {
        #expect(Garment.ID.random() != Garment.ID.random())
    }

    @Test func aFullGarmentSurvivesEncoding() throws {
        var garment = Make.garment("g-1", .bottom, colors: [.navy, .white])
        garment.fit = .relaxed
        garment.ownership = .purchased(.notArrived)
        garment.availability = .unavailable(until: TestTime.day(3))
        garment.deletedAt = TestTime.day(-1)
        garment.wornOn = [TestTime.day(-9), TestTime.day(-2)]
        garment.photo = .stored("photo-1")
        let decoded = try JSONDecoder().decode(Garment.self, from: JSONEncoder().encode(garment))
        #expect(decoded == garment)
    }

    @Test func lastWornIsTheLatestWear() {
        var garment = Make.garment("g-1", .top)
        #expect(garment.lastWorn == nil)
        garment.wornOn = [TestTime.day(-9), TestTime.day(-2)]
        #expect(garment.lastWorn == TestTime.day(-2))
    }

    @Test func recentlyDeletedKeepsAPieceForThirtyDays() {
        var garment = Make.garment("g-1", .top)
        #expect(garment.purgeDate == nil)
        garment.deletedAt = TestTime.now
        #expect(garment.purgeDate == TestTime.now.addingTimeInterval(30 * 86_400))
    }

    @Test(arguments: [
        (Ownership.owned, true),
        (.purchased(.notArrived), true),
        (.purchased(.arrived), true),
        (.wishlisted, false),
        (.noLongerOwned, false),
    ])
    func closetHoldsOwnedAndBoughtPieces(ownership: Ownership, inCloset: Bool) {
        #expect(Make.garment("g-1", .top, ownership: ownership).isInCloset == inCloset)
    }

    @Test func archivedAndDeletedPiecesLeaveCloset() {
        var archived = Make.garment("g-1", .top)
        archived.isArchived = true
        var deleted = Make.garment("g-2", .top)
        deleted.deletedAt = TestTime.now
        #expect(!archived.isInCloset)
        #expect(!deleted.isInCloset)
    }

    @Test func categoriesListInBodyOrder() {
        #expect(GarmentCategory.allCases.sorted() == [.layer, .top, .dress, .bottom, .shoes, .bag, .accessory])
    }

    @Test(arguments: [(3, Season.spring), (7, .summer), (10, .fall), (1, .winter), (12, .winter)])
    func seasonFollowsTheMonth(month: Int, season: Season) throws {
        let date = try #require(TestTime.calendar.date(from: DateComponents(year: 2026, month: month, day: 15)))
        #expect(Season.of(date, calendar: TestTime.calendar) == season)
    }
}

struct LookTests {
    @Test func separatesOwnedPiecesFromIdeas() {
        let idea = PieceIdea(name: "Cropped cardigan", category: .layer, colors: [.cream])
        let look = Make.look("o-1", version: .somethingNew, garments: ["g-1", "g-2"], idea: idea)
        #expect(look.garmentIDs == ["g-1", "g-2"])
        #expect(look.ideas == [idea])
        #expect(look.pieces.last?.isIdea == true)
        #expect(!look.isMadeByHer)
    }

    @Test func aLookWithoutAVersionIsHerOwn() {
        #expect(Make.look("o-1", version: nil, garments: ["g-1", "g-2"]).isMadeByHer)
    }

    @Test func aLookSurvivesEncoding() throws {
        let look = Make.look(
            "o-1",
            version: .somethingNew,
            garments: ["g-1", "g-2"],
            idea: PieceIdea(name: "Thin belt", category: .accessory),
            wornOn: [TestTime.day(-1)]
        )
        #expect(try JSONDecoder().decode(Look.self, from: JSONEncoder().encode(look)) == look)
    }
}

struct ProfileTests {
    @Test func aFreshProfileHasLilysDefaults() {
        let profile = Profile()
        #expect(profile.preferences.pieceMode == .mineAndOneIdea)  // LR-03.3
        #expect(profile.preferences.repeatWindow == .oneWeek)  // LR-10
        #expect(!profile.preferences.tracksLaundry)  // RD-11.1
        #expect(profile.signName.isEmpty)
        #expect(profile.measurements.isEmpty)
    }

    @Test func repeatWindowsInDays() {
        #expect(RepeatWindow.allCases.map(\.days) == [7, 14, nil])
    }

    @Test func comfortMatchesAGarmentCut() {
        #expect(Comfort.allCases.map(\.matchingFit) == [.fitted, .regular, .relaxed])
    }

    @Test func unitsConvert() {
        #expect(abs(Length(152.4, .centimeters).inches - 60) < 0.0001)
        #expect(abs(Weight(50, .kilograms).pounds - 110.231) < 0.001)
    }
}
