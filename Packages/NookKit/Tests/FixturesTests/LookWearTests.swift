import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

/// Wear today on a look writes to two stores (`LookWear`). If the pieces can't be written, the
/// look is put back, so the look and its pieces never disagree about the day.
struct LookWearTests {
    private let look = Look(
        id: "l1", pieces: [LookPiece(id: "p1", content: .garment("g1"))], name: "Office navy", isSaved: true,
        wornOn: [TestTime.day(-3)], createdAt: TestTime.day(-10))
    private let garment = Garment(id: "g1", name: "Navy trousers", category: .bottom, addedAt: TestTime.day(-20))

    private func stores(closetFails: Bool = false) -> (InMemoryLookStore, InMemoryClosetStore) {
        (
            InMemoryLookStore(looks: [look], calendar: TestTime.calendar),
            InMemoryClosetStore(
                garments: [garment], calendar: TestTime.calendar, options: StoreOptions(fails: closetFails))
        )
    }

    private var wear: LookWear { LookWear(lookID: "l1", garmentIDs: ["g1"], date: TestTime.now) }

    @Test func recordsOnTheLookAndItsPieces() async throws {
        let (looks, closet) = stores()
        try await wear.record(looks: looks, closet: closet)
        #expect(try await looks.look("l1").wornOn == [TestTime.day(-3), TestTime.now])
        #expect(try await closet.garment("g1").wornOn == [TestTime.now])

        try await wear.remove(looks: looks, closet: closet)
        #expect(try await looks.look("l1").wornOn == [TestTime.day(-3)])
        #expect(try await closet.garment("g1").wornOn.isEmpty)
    }

    @Test func aFailingClosetLeavesTheLookAsItWas() async throws {
        let (looks, closet) = stores(closetFails: true)
        await #expect(throws: StoreError.unavailable) { try await wear.record(looks: looks, closet: closet) }
        #expect(try await looks.look("l1") == look)
    }

    @Test func aFailingClosetOnUndoPutsTheLooksWearBack() async throws {
        let worn = LookWear(lookID: "l1", garmentIDs: ["g1"], date: TestTime.day(-3))
        let (looks, closet) = stores(closetFails: true)
        await #expect(throws: StoreError.unavailable) { try await worn.remove(looks: looks, closet: closet) }
        #expect(try await looks.look("l1") == look)
    }

    @Test func anUnknownLookChangesNothing() async throws {
        let (looks, closet) = stores()
        let missing = LookWear(lookID: "nope", garmentIDs: ["g1"], date: TestTime.now)
        await #expect(throws: StoreError.notFound) { try await missing.record(looks: looks, closet: closet) }
        #expect(try await closet.garment("g1").wornOn.isEmpty)
    }
}
