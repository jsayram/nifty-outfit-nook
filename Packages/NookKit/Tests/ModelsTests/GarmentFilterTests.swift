import Foundation
import Models
import Testing

struct GarmentFilterTests {
    private let garments: [Garment] = {
        var jeans = Make.garment("g-jeans", .bottom, colors: [.denim])
        jeans.name = "Wide-leg jeans"
        jeans.brand = "Example Denim"
        var skirt = Make.garment("g-skirt", .bottom, colors: [.black])
        skirt.name = "Black midi skirt"
        var tee = Make.garment("g-tee", .top, colors: [.black, .white])
        tee.name = "Striped tee"
        var blouse = Make.garment("g-blouse", .top, colors: [.pink])
        blouse.name = "Café blouse"
        blouse.colorNote = "Light pink"
        return [jeans, skirt, tee, blouse]
    }()

    private let suitcases = [
        Suitcase(id: "s-weekend", name: "Weekend", garmentIDs: ["g-jeans", "g-tee"], createdAt: TestTime.now),
        Suitcase(id: "s-jose", name: "Jose's house", garmentIDs: ["g-tee"], createdAt: TestTime.now),
        Suitcase(id: "s-old", name: "Old dorm", garmentIDs: ["g-skirt"], isArchived: true, createdAt: TestTime.now),
    ]

    private func ids(_ filter: GarmentFilter) -> [Garment.ID] {
        filter.apply(to: garments, suitcases: suitcases).map(\.id)
    }

    @Test func anEmptyFilterMatchesEverything() {
        #expect(!GarmentFilter().isActive)
        #expect(ids(GarmentFilter()) == ["g-jeans", "g-skirt", "g-tee", "g-blouse"])
        #expect(!GarmentFilter(query: "   ").isActive)
    }

    @Test func pieceChipsAndSwatchesFilterAloneAndTogether() {
        // LR-09.1
        #expect(ids(GarmentFilter(categories: [.bottom])) == ["g-jeans", "g-skirt"])
        #expect(ids(GarmentFilter(colors: [.black])) == ["g-skirt", "g-tee"])
        #expect(ids(GarmentFilter(categories: [.bottom], colors: [.black])) == ["g-skirt"])
        #expect(ids(GarmentFilter(categories: [.top, .bottom], colors: [.pink, .denim])) == ["g-jeans", "g-blouse"])
    }

    @Test func typedTextCombinesWithFilters() {
        #expect(ids(GarmentFilter(colors: [.black], query: "tee")) == ["g-tee"])
    }

    @Test func textMatchesNameBrandAndColourNoteIgnoringCaseAndAccents() {
        #expect(ids(GarmentFilter(query: "WIDE")) == ["g-jeans"])
        #expect(ids(GarmentFilter(query: "example denim")) == ["g-jeans"])
        #expect(ids(GarmentFilter(query: "light pink")) == ["g-blouse"])
        #expect(ids(GarmentFilter(query: "cafe")) == ["g-blouse"])
    }

    @Test func textMatchesSuitcaseNames() {
        // LR-11.3
        #expect(ids(GarmentFilter(query: "jose")) == ["g-tee"])
        #expect(ids(GarmentFilter(query: "weekend")) == ["g-jeans", "g-tee"])
        #expect(ids(GarmentFilter(query: "dorm")).isEmpty)  // archived suitcase
    }

    @Test func suitcaseFilter() {
        // LR-11.2
        #expect(ids(GarmentFilter(packing: .inASuitcase)) == ["g-jeans", "g-tee"])
        #expect(ids(GarmentFilter(packing: .notPacked)) == ["g-skirt", "g-blouse"])
        #expect(ids(GarmentFilter(packing: .suitcase("s-jose"))) == ["g-tee"])
        #expect(ids(GarmentFilter(packing: .suitcase("s-old"))).isEmpty)
    }
}
