import Foundation
import Models
import Testing

@testable import Fixtures

struct ClosetStoreTests {
    private let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
    private var store: InMemoryClosetStore { InMemoryClosetStore(garments: data.garments, calendar: TestTime.calendar) }

    @Test func listsEveryGarmentNewestFirst() async throws {
        let garments = try await store.garments()
        #expect(garments.count == 21)
        #expect(garments.first?.id == "g-cream-crop")
        #expect(zip(garments, garments.dropFirst()).allSatisfy { $0.addedAt >= $1.addedAt })
    }

    @Test func unknownIDsAreNotFound() async {
        await #expect(throws: StoreError.notFound) { try await store.garment("g-nope") }
        await #expect(throws: StoreError.notFound) {
            try await store.setLaundry(.dirty, for: ["g-black-tee", "g-nope"])
        }
    }

    @Test func saveChecksAndTrimsTheName() async throws {
        let store = store
        var garment = try await store.garment("g-black-tee")
        garment.name = "  Old black tee "
        try await store.save(garment)
        #expect(try await store.garment("g-black-tee").name == "Old black tee")
        garment.name = " "
        await #expect(throws: StoreError.invalidName(.empty)) { try await store.save(garment) }
    }

    @Test func updateChangesOnePiece() async throws {
        let store = store
        let updated = try await store.update("g-black-tee") { $0.colors = [.gray] }
        #expect(updated.colors == [.gray])
        #expect(try await store.garment("g-black-tee").colors == [.gray])
    }

    @Test func wearTodayRecordsOncePerDayAndUndoes() async throws {
        let store = store
        try await store.recordWear(of: ["g-black-tee", "g-wide-jeans"], on: TestTime.now)
        try await store.recordWear(of: ["g-black-tee"], on: TestTime.now.addingTimeInterval(60))
        #expect(try await store.garment("g-black-tee").wornOn == [TestTime.now])
        #expect(try await store.garment("g-wide-jeans").lastWorn == TestTime.now)
        try await store.removeWear(of: ["g-black-tee"], on: TestTime.now)
        #expect(try await store.garment("g-black-tee").wornOn.isEmpty)
    }

    @Test func wearTodayLeavesLaundryAlone() async throws {
        // LR-10.4
        let store = store
        try await store.recordWear(of: ["g-lace-top", "g-pink-blouse"], on: TestTime.now)
        #expect(try await store.garment("g-lace-top").laundry == .dirty)
        #expect(try await store.garment("g-pink-blouse").laundry == .clean)
    }

    @Test func deleteRestoreAndPurge() async throws {
        // LR-16.2 and LR-16.3
        let store = store
        try await store.delete("g-black-tee", at: TestTime.now)
        #expect(try await store.garment("g-black-tee").isDeleted)
        try await store.restore("g-black-tee")
        #expect(try await store.garment("g-black-tee").isDeleted == false)

        // The demo leggings were deleted 3 days ago: still there after 26 days, gone after 27.
        #expect(try await store.purgeExpired(asOf: TestTime.day(26)).isEmpty)
        #expect(try await store.purgeExpired(asOf: TestTime.day(27)) == ["g-gray-leggings"])
        await #expect(throws: StoreError.notFound) { try await store.garment("g-gray-leggings") }
    }

    @Test func aFailingStoreFailsEveryCall() async {
        let store = InMemoryClosetStore(garments: [], calendar: TestTime.calendar, options: StoreOptions(fails: true))
        await #expect(throws: StoreError.unavailable) { try await store.garments() }
    }

    @Test func aSlowStoreCanBeCancelled() async {
        let store = InMemoryClosetStore(
            garments: data.garments,
            calendar: TestTime.calendar,
            options: StoreOptions(latency: .seconds(30))
        )
        let task = Task { try await store.garments() }
        task.cancel()
        await #expect(throws: StoreError.cancelled) { try await task.value }
    }
}

struct LookStoreTests {
    private let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
    private var store: InMemoryLookStore { InMemoryLookStore(looks: data.looks, calendar: TestTime.calendar) }

    @Test func listsNewestFirst() async throws {
        let looks = try await store.looks()
        #expect(looks.count == data.looks.count)
        #expect(zip(looks, looks.dropFirst()).allSatisfy { $0.createdAt >= $1.createdAt })
    }

    @Test func namesAreCheckedWhenSaving() async throws {
        let store = store
        var look = try await store.look("o-history-casual")
        look.isSaved = true
        look.name = "  Rainy Sunday "
        try await store.save(look)
        #expect(try await store.look("o-history-casual").name == "Rainy Sunday")
        await #expect(throws: StoreError.invalidName(.empty)) {
            try await store.update("o-history-casual") { $0.name = "" }
        }
    }

    @Test func wearTodayAndUndo() async throws {
        // LR-10.1
        let store = store
        try await store.recordWear(of: "o-lace-date", on: TestTime.now)
        #expect(try await store.look("o-lace-date").lastWorn == TestTime.now)
        try await store.removeWear(of: "o-lace-date", on: TestTime.now)
        #expect(try await store.look("o-lace-date").lastWorn == TestTime.day(-70))
    }

    @Test func deleteRemovesTheLook() async throws {
        let store = store
        try await store.delete("o-lace-date")
        await #expect(throws: StoreError.notFound) { try await store.look("o-lace-date") }
        await #expect(throws: StoreError.notFound) { try await store.delete("o-lace-date") }
    }
}

struct SuitcaseStoreTests {
    private let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
    private var store: InMemorySuitcaseStore {
        InMemorySuitcaseStore(suitcases: data.suitcases, makeID: { "s-new" })
    }

    @Test func addASuitcaseWithAUniqueName() async throws {
        // LR-17.2
        let store = InMemorySuitcaseStore(suitcases: [], makeID: { "s-new" })
        let created = try await store.create(name: " Ski trip ", icon: .duffel, at: TestTime.now)
        #expect(created == Suitcase(id: "s-new", name: "Ski trip", icon: .duffel, createdAt: TestTime.now))
        #expect(try await store.suitcases() == [created])
        await #expect(throws: StoreError.invalidName(.duplicate)) {
            try await store.create(name: "SKI TRIP", icon: .tote, at: TestTime.now)
        }
    }

    @Test func renamingKeepsNamesUnique() async throws {
        let store = store
        await #expect(throws: StoreError.invalidName(.duplicate)) {
            try await store.update(DemoCloset.gym) { $0.name = "weekend" }
        }
        let renamed = try await store.update(DemoCloset.gym) { $0.name = "Gym bag" }
        #expect(renamed.name == "Gym bag")
    }

    @Test func packAndUnpack() async throws {
        let store = store
        try await store.add(["g-tan-loafers", "g-tan-loafers"], to: DemoCloset.springTrip)
        #expect(try await store.suitcase(DemoCloset.springTrip).garmentIDs == ["g-tan-loafers"])
        try await store.remove(["g-tan-loafers"], from: DemoCloset.springTrip)
        #expect(try await store.suitcase(DemoCloset.springTrip).garmentIDs.isEmpty)
    }

    @Test func usingASuitcaseMakesItAFavourite() async throws {
        // RD-09.2
        let store = store
        try await store.markUsed(DemoCloset.beach, at: TestTime.now)
        let shelf = SuitcaseShelf(try await store.suitcases())
        #expect(shelf.favorites.first?.id == DemoCloset.beach)
    }

    @Test func deletingASuitcaseKeepsTheClothes() async throws {
        let store = store
        try await store.delete(DemoCloset.weekend)
        #expect(try await store.suitcases().count == data.suitcases.count - 1)
    }
}

struct ProfileStoreTests {
    @Test func savesAndTrimsTheSignName() async throws {
        let store = InMemoryProfileStore(profile: Profile())
        try await store.save(Profile(signName: " Lily "))
        #expect(try await store.profile().signName == "Lily")
    }

    @Test func refusesImpossibleMeasurements() async throws {
        let store = InMemoryProfileStore(profile: Profile())
        var profile = Profile()
        profile.measurements.inseam = Length(200, .inches)
        await #expect(throws: StoreError.invalidMeasurements([MeasurementProblem(field: .inseam, allowed: 15...45)])) {
            try await store.save(profile)
        }
        #expect(try await store.profile() == Profile())
    }

    @Test func refusesAFitPieceWithoutABrand() async {
        let store = InMemoryProfileStore(profile: Profile())
        let profile = Profile(fitPieces: [FitPiece(id: "f-1", brand: "", category: .top, sizeLabel: "S")])
        await #expect(throws: StoreError.invalidName(.empty)) { try await store.save(profile) }
    }
}
