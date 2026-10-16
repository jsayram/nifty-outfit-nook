import Foundation
import Models
import NookTestSupport
import Testing

/// LR-07: the pieces Swap a piece offers, ranked on the phone from stored facts only.
struct SwapRankingTests {
    private static func piece(
        _ id: Garment.ID, _ category: GarmentCategory, colors: [ColorName] = [.white],
        occasions: Set<Occasion> = [.office], warmth: Warmth = .medium, fit: GarmentFit? = nil,
        dressiness: Dressiness = .smart, laundry: LaundryState = .clean, ownership: Ownership = .owned,
        wornOn: [Date] = []
    ) -> Garment {
        Garment(
            id: id, name: "Piece \(id)", category: category, colors: colors, fit: fit, dressiness: dressiness,
            warmth: warmth, occasions: occasions, ownership: ownership, laundry: laundry, wornOn: wornOn,
            addedAt: TestTime.day(-30))
    }

    private let closet: [Garment] = [
        piece("top", .top, colors: [.pink]),
        piece("bottom", .bottom, colors: [.pink]),
        piece("shoes", .shoes, colors: [.beige]),
        // Tops to swap in.
        piece("top-cream", .top, colors: [.cream], fit: .relaxed),
        piece("top-pink2", .top, colors: [.pink], dressiness: .dressy),
        piece("top-green", .top, colors: [.green]),
        piece("top-casual", .top, colors: [.white], occasions: [.casual]),
        piece("top-dirty", .top, colors: [.white], laundry: .dirty),
        piece("top-wish", .top, colors: [.white], ownership: .wishlisted),
        piece("top-warm", .top, colors: [.white], warmth: .warm),
        piece("top-old", .top, colors: [.white], wornOn: [TestTime.day(-40)]),
    ]

    private var byID: [Garment.ID: Garment] { Dictionary(uniqueKeysWithValues: closet.map { ($0.id, $0) }) }
    private let look = Make.look("look", garments: ["top", "bottom", "shoes"])

    private func situation(
        members: Set<Garment.ID>? = nil, tracksLaundry: Bool = true, weather: WeatherSnapshot? = nil,
        fit: GarmentFit? = nil, recent: [Set<Garment.ID>: Date] = [:]
    ) -> SwapSituation {
        SwapSituation(
            members: members, occasion: .office, weather: weather, fit: fit, tracksLaundry: tracksLaundry,
            recentCombinations: recent, date: TestTime.now, calendar: TestTime.calendar)
    }

    @Test func optionsAreTheSameKindAndCanBeWorn() throws {
        let options = try #require(
            SwapRanking.options(for: "look-top", in: look, garments: byID, situation: situation()))
        #expect(options.category == .top)
        let offered = Set(options.all)
        #expect(!offered.contains("top"), "The piece in the look isn't offered")
        #expect(!offered.contains("top-dirty"), "In the wash while tracking")
        #expect(!offered.contains("top-wish"), "Not hers")
        #expect(offered.allSatisfy { byID[$0]?.category == .top })
        // With tracking off, the dirty one can be worn (RD-11.2).
        let untracked = try #require(
            SwapRanking.options(for: "look-top", in: look, garments: byID, situation: situation(tracksLaundry: false)))
        #expect(untracked.all.contains("top-dirty"))
    }

    /// LR-07.2: only pieces from the current source.
    @Test func aSuitcaseOffersOnlyWhatsPacked() throws {
        let options = try #require(
            SwapRanking.options(
                for: "look-top", in: look, garments: byID,
                situation: situation(members: ["top", "bottom", "shoes", "top-cream", "top-green"])))
        #expect(Set(options.all) == ["top-cream", "top-green"])
    }

    /// Plain matching: occasion, colours that sit with the rest, and the replaced piece's
    /// dressiness add up; ties go to the one worn longest ago, then by name.
    @Test func betterMatchesComeFirst() throws {
        let options = try #require(
            SwapRanking.options(for: "look-top", in: look, garments: byID, situation: situation(fit: .relaxed)))
        // top-cream: office, colours go, smart like the pink top, relaxed fit. Then two smart
        // white tops: the one never worn before the one worn 40 days ago. Then the dressy pink.
        #expect(options.ranked == ["top-cream", "top-warm", "top-old", "top-pink2"])
        // Green with the pink trousers shares no family and neither is neutral, so it may not
        // match; the casual top isn't tagged for the office.
        #expect(options.weaker == ["top-casual", "top-green"])
    }

    @Test func weatherMakesAPieceWeaker() throws {
        let hot = WeatherSnapshot(condition: .sun, temperatureCelsius: 30, observedAt: TestTime.now)
        let options = try #require(
            SwapRanking.options(for: "look-top", in: look, garments: byID, situation: situation(weather: hot)))
        #expect(options.weaker.contains("top-warm"))
        #expect(!options.ranked.contains("top-warm"))
    }

    /// LR-10: a swap that would rebuild an outfit worn inside the repeat window isn't suggested.
    @Test func anOutfitWornRecentlyIsLeftForSeeAll() throws {
        let worn = TestTime.day(-3)
        let options = try #require(
            SwapRanking.options(
                for: "look-top", in: look, garments: byID,
                situation: situation(recent: [["top-cream", "bottom"]: worn])))
        #expect(!options.ranked.contains("top-cream"))
        #expect(options.wornRecently == ["top-cream": worn])
        #expect(options.all.last == "top-cream")
        // Shoes don't make a main-piece combination, so they repeat freely.
        let shoes = try #require(
            SwapRanking.options(
                for: "look-shoes", in: look, garments: byID, situation: situation(recent: [["top", "bottom"]: worn])))
        #expect(shoes.wornRecently.isEmpty)
    }

    @Test func anIdeaPieceIsSwappedForOwnedPiecesOfItsKind() throws {
        let idea = PieceIdea(name: "Cropped cardigan", category: .layer, colors: [.cream])
        let withIdea = Make.look("new", version: .somethingNew, garments: ["top", "bottom", "shoes"], idea: idea)
        var garments = byID
        garments["cardigan"] = Self.piece("cardigan", .layer, colors: [.navy])
        let options = try #require(
            SwapRanking.options(for: "new-idea", in: withIdea, garments: garments, situation: situation()))
        #expect(options.category == .layer)
        #expect(options.ranked == ["cardigan"])
    }

    @Test func anUnknownPieceHasNoOptions() {
        #expect(SwapRanking.options(for: "nope", in: look, garments: byID, situation: situation()) == nil)
    }

    @Test func coloursThatGoTogether() {
        #expect(SwapRanking.colorsGo([.pink], with: [.navy]), "Navy is neutral")
        #expect(SwapRanking.colorsGo([.pink], with: [.pink, .white]))
        #expect(SwapRanking.colorsGo([], with: [.red]), "Unknown colour")
        #expect(SwapRanking.colorsGo([.multicolor], with: [.green]))
        #expect(!SwapRanking.colorsGo([.green], with: [.pink]))
        #expect(SwapRanking.colorsGo([.red], with: [.purple, .red]), "A shared family")
        #expect(!SwapRanking.colorsGo([.red, .white], with: [.purple]), "Only the main colour counts as neutral")
    }
}
