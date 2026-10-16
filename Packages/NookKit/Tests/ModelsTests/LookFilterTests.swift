import Foundation
import Models
import Testing

/// Saved Looks' search and filters (RD-08.3, LR-09.1).
struct LookFilterTests {
    private let garments: [Garment.ID: Garment] = {
        var skirt = Make.garment("g-skirt", .bottom, colors: [.black])
        skirt.name = "Black midi skirt"
        var jeans = Make.garment("g-jeans", .bottom, colors: [.denim])
        jeans.name = "Wide-leg jeans"
        var tee = Make.garment("g-tee", .top, colors: [.black, .white])
        tee.name = "Striped tee"
        var blouse = Make.garment("g-blouse", .top, colors: [.pink])
        blouse.name = "Café blouse"
        var heels = Make.garment("g-heels", .shoes, colors: [.black])
        heels.name = "Block heels"
        return Dictionary(uniqueKeysWithValues: [skirt, jeans, tee, blouse, heels].map { ($0.id, $0) })
    }()

    private var looks: [Look] {
        var date = Make.look("o-date", garments: ["g-blouse", "g-skirt", "g-heels"])
        date.name = "Date night pink"
        date.occasion = .dateNight
        var weekend = Make.look(
            "o-weekend", garments: ["g-tee", "g-jeans"],
            idea: PieceIdea(name: "Cream cardigan", category: .layer, colors: [.cream]))
        weekend.name = "Easy weekend"
        weekend.occasion = .casual
        // A piece that was deleted for good: nothing left to match.
        var gone = Make.look("o-gone", garments: ["g-purged", "g-jeans"])
        gone.name = "Old favourite"
        return [date, weekend, gone]
    }

    private func ids(_ filter: LookFilter, extraWords: (Look) -> [String] = { _ in [] }) -> [Look.ID] {
        filter.apply(to: looks, garments: garments, extraWords: extraWords).map(\.id)
    }

    @Test func anEmptyFilterMatchesEverything() {
        #expect(!LookFilter().isActive)
        #expect(!LookFilter(query: "  ").isActive)
        #expect(ids(LookFilter()) == ["o-date", "o-weekend", "o-gone"])
    }

    /// LR-09.1: each chip and swatch alone.
    @Test func chipsAndSwatchesFilterAlone() {
        #expect(ids(LookFilter(categories: [.bottom])) == ["o-date", "o-weekend", "o-gone"])
        #expect(ids(LookFilter(categories: [.shoes])) == ["o-date"])
        #expect(ids(LookFilter(colors: [.black])) == ["o-date", "o-weekend"])
        #expect(ids(LookFilter(colors: [.pink])) == ["o-date"])
        // An idea counts as a piece.
        #expect(ids(LookFilter(categories: [.layer])) == ["o-weekend"])
        #expect(ids(LookFilter(colors: [.cream])) == ["o-weekend"])
    }

    /// "Black bottoms" means a bottom that's black, not any bottom with something black.
    @Test func aChipAndASwatchMatchOnePiece() {
        #expect(ids(LookFilter(categories: [.bottom], colors: [.black])) == ["o-date"])
        // The weekend look has a black tee and denim jeans: no black bottom.
        #expect(!ids(LookFilter(categories: [.bottom], colors: [.black])).contains("o-weekend"))
        // Two chips: any piece of either kind in that colour.
        #expect(ids(LookFilter(categories: [.bottom, .top], colors: [.black])) == ["o-date", "o-weekend"])
        // Two swatches: either colour.
        #expect(ids(LookFilter(colors: [.pink, .denim])) == ["o-date", "o-weekend", "o-gone"])
    }

    /// RD-08.3: typed words match the look's name and its pieces' names, ignoring case and accents.
    @Test func searchMatchesNamesAndPieces() {
        #expect(ids(LookFilter(query: "weekend")) == ["o-weekend"])
        #expect(ids(LookFilter(query: "SKIRT")) == ["o-date"])
        #expect(ids(LookFilter(query: "cafe")) == ["o-date"])
        #expect(ids(LookFilter(query: "cardigan")) == ["o-weekend"])
        // Every word must match somewhere.
        #expect(ids(LookFilter(query: "jeans striped")) == ["o-weekend"])
        #expect(ids(LookFilter(query: "jeans heels")).isEmpty)
        #expect(ids(LookFilter(query: "nothing")).isEmpty)
    }

    /// The screen passes the occasion's name and kind and colour words.
    @Test func extraWordsCount() {
        let occasion: (Look) -> [String] = { look in look.occasion == .dateNight ? ["Date night"] : [] }
        #expect(ids(LookFilter(query: "date"), extraWords: occasion) == ["o-date"])
        let pieces = LookFilter.pieces(of: looks[0], garments: garments)
        let filter = LookFilter(query: "shoes")
        #expect(filter.matches(name: "Date night pink", pieces: pieces) == false)
        #expect(
            filter.matches(name: "Date night pink", pieces: pieces) { $0.category == .shoes ? ["Shoes"] : [] })
    }

    /// Chips, swatches and text together.
    @Test func everythingCombines() {
        #expect(ids(LookFilter(categories: [.bottom], query: "pink")) == ["o-date"])
        #expect(ids(LookFilter(categories: [.bottom], colors: [.denim], query: "pink")).isEmpty)
        #expect(ids(LookFilter(colors: [.black], query: "easy")) == ["o-weekend"])
    }

    /// A purged piece is left out of the look's pieces; the rest still match.
    @Test func goneGarmentsAreLeftOut() {
        let pieces = LookFilter.pieces(of: looks[2], garments: garments)
        #expect(pieces.map(\.name) == ["Wide-leg jeans"])
        #expect(ids(LookFilter(query: "old favourite")) == ["o-gone"])
    }

    @Test func activeAndChoices() {
        #expect(LookFilter(categories: [.top]).hasChoices)
        #expect(LookFilter(colors: [.black]).isActive)
        #expect(!LookFilter(query: "navy").hasChoices)
        #expect(LookFilter(query: " navy  blue ").words == ["navy", "blue"])
    }
}
