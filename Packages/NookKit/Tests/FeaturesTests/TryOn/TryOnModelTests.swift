import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Try it on (Phase 12b, RD-06): what the sheet shows first, making a picture and keeping it,
/// a picture she already has (FR-59), failures, Cancel, and saving a look from Your looks first.
@MainActor
struct TryOnModelTests {
    /// Demo services with a Try it on that answers at once (or fails, or waits), and new picture
    /// IDs that tests can predict.
    private func services(
        _ mode: SimulatedTryOn.Mode = .normal, latency: Duration = .zero, behavior: FixtureBehavior = .normal
    ) -> NookServices {
        var services = FixtureServices.make(
            set: .demo, behavior: behavior, now: TestTime.now, calendar: TestTime.calendar)
        services.tryOn = SimulatedTryOn(mode: mode, latency: latency, makeID: { "p-new" })
        return services
    }

    private func look(_ id: Look.ID, in services: NookServices) async throws -> Look {
        try await services.looks.look(id)
    }

    private func model(for look: Look, saveLook: (() async throws(StoreError) -> Look)? = nil) -> TryOnModel {
        TryOnModel(
            look: look, lookName: look.name ?? "Look", garments: [:], saveLook: saveLook, now: { TestTime.now })
    }

    /// The sheet says what will happen and makes nothing until she taps Make a picture (RD-06.2).
    @Test func makesAPictureOnlyWhenAskedAndKeepsIt() async throws {
        let services = services()
        let blazer = try await look("o-blazer-office", in: services)
        let model = model(for: blazer)
        await model.start(with: services)
        #expect(model.step == .ready)
        #expect(!model.savesLook)
        #expect(try await services.pictures.pictures().count == 3)

        model.make()
        #expect(model.step == .making)
        await model.settle()
        let picture = try await services.pictures.picture("p-new")
        #expect(model.step == .made(picture))
        #expect(picture.lookID == "o-blazer-office")
        #expect(picture.captured == CapturedLook(blazer))
        #expect(picture.createdAt == TestTime.now)
    }

    /// FR-59: a picture of exactly this look is offered first; Make another still makes one.
    @Test func offersAPictureSheAlreadyHas() async throws {
        let services = services()
        let interview = try await look("o-interview", in: services)
        let model = model(for: interview)
        await model.start(with: services)
        let existing = try await services.pictures.picture("p-interview")
        #expect(model.step == .alreadyMade(existing))

        model.make()
        await model.settle()
        #expect(try await services.pictures.pictures().count == 4)
        #expect(model.step == .made(try await services.pictures.picture("p-new")))
    }

    /// Offline or not finished: nothing is kept, and Try again works once it can.
    @Test func failuresKeepNothing() async throws {
        let offline = services(.failing(.offline))
        let blazer = try await look("o-blazer-office", in: offline)
        let model = model(for: blazer)
        await model.start(with: offline)
        model.make()
        await model.settle()
        #expect(model.step == .failed(.offline))
        #expect(try await offline.pictures.pictures().count == 3)

        let unfinished = services(.failing(.notCompleted))
        let other = self.model(for: blazer)
        await other.start(with: unfinished)
        other.make()
        await other.settle()
        #expect(other.step == .failed(.notCompleted))
    }

    /// A picture that can't be kept isn't shown as ready.
    @Test func aPictureThatCantBeKeptIsNotReady() async throws {
        let working = services()
        let blazer = try await look("o-blazer-office", in: working)
        var failingStore = services()
        failingStore.pictures = InMemoryTryOnPictureStore(pictures: [], options: StoreOptions(fails: true))
        let model = model(for: blazer)
        await model.start(with: failingStore)
        // An unreadable store just means no picture is offered for reuse.
        #expect(model.step == .ready)
        model.make()
        await model.settle()
        #expect(model.step == .failed(.notSaved))
    }

    /// Cancel while making: back to the start, nothing kept.
    @Test func cancelKeepsNothing() async throws {
        let services = services(latency: .seconds(30))
        let blazer = try await look("o-blazer-office", in: services)
        let model = model(for: blazer)
        await model.start(with: services)
        model.make()
        #expect(model.step == .making)
        model.cancel()
        #expect(model.step == .ready)
        await model.settle()
        #expect(model.step == .ready)
        #expect(try await services.pictures.pictures().count == 3)
    }

    /// From Your looks, a look that isn't saved is saved first, and the picture keeps its name.
    @Test func savesTheLookFirstFromYourLooks() async throws {
        let services = services()
        let history = try await look("o-history-casual", in: services)
        #expect(!history.isSaved)
        let looks = services.looks
        let model = model(for: history) { () async throws(StoreError) -> Look in
            try await looks.update(history.id) { look in
                look.isSaved = true
                look.name = "Cream & denim"
                look.savedAt = TestTime.now
            }
        }
        #expect(model.savesLook)
        await model.start(with: services)
        model.make()
        await model.settle()
        let picture = try await services.pictures.picture("p-new")
        #expect(model.step == .made(picture))
        #expect(picture.captured.name == "Cream & denim")
        #expect(try await looks.look(history.id).isSaved)
        let all = try await services.looks.looks()
        #expect(
            TryOnLinks.status(of: picture, looks: Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) }))
                != .notSaved)
    }

    @Test func failureWords() {
        #expect(TryOnSheetText.failedTitle(.offline) == "Pictures need a connection")
        #expect(TryOnSheetText.failedMessage(.offline) == "Nothing was made or used. Try again when you’re online.")
        #expect(TryOnSheetText.failedTitle(.notCompleted) == "The picture didn’t finish")
        #expect(TryOnSheetText.failedTitle(.notSaved) == "The picture couldn’t be kept")
    }
}
