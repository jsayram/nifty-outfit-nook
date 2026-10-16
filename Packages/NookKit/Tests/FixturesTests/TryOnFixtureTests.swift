import Foundation
import Models
import Testing

@testable import Fixtures

/// The picture store, the simulated Try it on and the fixture pictures (Phase 12b).
struct TryOnFixtureTests {
    private let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)

    private func look(_ id: Look.ID) throws -> Look {
        try #require(data.looks.first { $0.id == id })
    }

    // MARK: The store

    @Test func listsPicturesNewestFirst() async throws {
        let store = InMemoryTryOnPictureStore(pictures: data.pictures)
        #expect(try await store.pictures().map(\.id) == ["p-interview", "p-interview-earlier", "p-lace"])
        #expect(try await store.picture("p-lace").lookID == "o-lace-date")
        await #expect(throws: StoreError.notFound) { try await store.picture("p-nope") }
    }

    /// Delete picture removes it; saving the same picture again (Undo) brings it back as it was.
    @Test func deleteThenSaveAgain() async throws {
        let store = InMemoryTryOnPictureStore(pictures: data.pictures)
        let lace = try await store.picture("p-lace")
        try await store.delete("p-lace")
        #expect(try await store.pictures().map(\.id) == ["p-interview", "p-interview-earlier"])
        await #expect(throws: StoreError.notFound) { try await store.delete("p-lace") }
        try await store.save(lace)
        #expect(try await store.picture("p-lace") == lace)
    }

    @Test func aFailingStoreFails() async {
        let store = InMemoryTryOnPictureStore(pictures: data.pictures, options: StoreOptions(fails: true))
        await #expect(throws: StoreError.unavailable) { try await store.pictures() }
    }

    // MARK: Simulated Try it on

    /// A simulated picture of the look as it is: no image file, nothing sent.
    @Test func makesASimulatedPictureOfTheLook() async throws {
        let interview = try look("o-interview")
        let service = SimulatedTryOn(makeID: { "p-new" })
        let picture = try await service.makePicture(of: interview, at: TestTime.now)
        #expect(picture.id == "p-new")
        #expect(picture.lookID == interview.id)
        #expect(picture.captured == CapturedLook(interview))
        #expect(picture.image == .simulated)
        #expect(picture.createdAt == TestTime.now)
    }

    @Test func failsWhenAskedTo() async throws {
        let interview = try look("o-interview")
        await #expect(throws: TryOnError.offline) {
            try await SimulatedTryOn(mode: .failing(.offline)).makePicture(of: interview, at: TestTime.now)
        }
        await #expect(throws: TryOnError.notCompleted) {
            try await SimulatedTryOn(mode: .failing(.notCompleted)).makePicture(of: interview, at: TestTime.now)
        }
    }

    @Test func cancellingStopsIt() async throws {
        let interview = try look("o-interview")
        let service = SimulatedTryOn(latency: .seconds(30))
        let task = Task { try await service.makePicture(of: interview, at: TestTime.now) }
        task.cancel()
        await #expect(throws: TryOnError.cancelled) { try await task.value }
    }

    // MARK: Fixture sets

    /// The demo's pictures: two of Interview (one of an earlier version with the cream sweater)
    /// and one of Lace date night, each linked to a saved look.
    @Test func demoPicturesLinkToSavedLooks() throws {
        let looks = Dictionary(uniqueKeysWithValues: data.looks.map { ($0.id, $0) })
        let statuses = data.pictures.map { TryOnLinks.status(of: $0, looks: looks) }
        let interview = try look("o-interview")
        let lace = try look("o-lace-date")
        #expect(statuses == [.current(interview), .changed(interview), .current(lace)])
        let earlier = try #require(data.pictures.first { $0.id == "p-interview-earlier" })
        #expect(earlier.captured.pieces.compactMap(\.garmentID).contains("g-cream-sweater"))
        #expect(!earlier.captured.pieces.compactMap(\.garmentID).contains("g-pink-blouse"))
        #expect(data.pictures.allSatisfy { $0.image == .simulated })
    }

    @Test func emptyHasNoPictures() {
        #expect(FixtureSet.empty.data(now: TestTime.now, calendar: TestTime.calendar).pictures.isEmpty)
    }

    /// The large set: a picture for every third saved look, each of a saved look.
    @Test func largeSetHasPicturesOfSavedLooks() {
        let large = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar)
        let saved = large.looks.filter(\.isSaved)
        #expect(large.pictures.count == (saved.count + 2) / 3)
        let looks = Dictionary(uniqueKeysWithValues: large.looks.map { ($0.id, $0) })
        #expect(large.pictures.allSatisfy { TryOnLinks.status(of: $0, looks: looks) != .notSaved })
    }

    /// `offline` and `picture-fails` make Try it on fail; stores-fail fails the picture store.
    @Test func behavioursReachTryOn() async throws {
        let interview = try look("o-interview")
        let offline = FixtureServices.make(
            set: .demo, behavior: .offline, now: TestTime.now, calendar: TestTime.calendar)
        await #expect(throws: TryOnError.offline) {
            try await offline.tryOn.makePicture(of: interview, at: TestTime.now)
        }
        let fails = FixtureServices.make(
            set: .demo, behavior: .pictureFails, now: TestTime.now, calendar: TestTime.calendar)
        await #expect(throws: TryOnError.notCompleted) {
            try await fails.tryOn.makePicture(of: interview, at: TestTime.now)
        }
        let storesFail = FixtureServices.make(
            set: .demo, behavior: .storesFail, now: TestTime.now, calendar: TestTime.calendar)
        await #expect(throws: StoreError.unavailable) { try await storesFail.pictures.pictures() }
        let normal = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        #expect(try await normal.pictures.pictures().count == 3)
        #expect(FixtureConfiguration(launchArguments: ["-fixtures", "demo:picture-fails"]).behavior == .pictureFails)
    }
}
