import Fixtures
import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Features

/// 33a: Try it on with real pictures: her consent first (nothing prepared or sent without it),
/// the phone's checks refusing kindly with nothing sent, and the picture made as a background
/// job she can leave.
@MainActor
struct RealTryOnModelTests {
    private func services(_ pipeline: StubPipeline, consent: TryOnConsent? = nil) -> NookServices {
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        services.tryOnPipeline = pipeline
        services.tryOnIsSimulated = false
        services.tryOnConsent = InMemoryTryOnConsentStore(consent)
        services.subscriptions = ScriptedSubscriptionService.debug("active", now: TestTime.now)
        services.aiJobs = AIJobs(now: { TestTime.now })
        return services
    }

    private func model(_ services: NookServices) async throws -> TryOnModel {
        let look = try await services.looks.look("o-blazer-office")
        let garments = Dictionary(uniqueKeysWithValues: try await services.closet.garments().map { ($0.id, $0) })
        return TryOnModel(look: look, lookName: "Blazer", garments: garments, now: { TestTime.now })
    }

    @Test func noConsentMeansNothingIsPreparedOrSent() async throws {
        let pipeline = StubPipeline()
        let services = services(pipeline)
        let model = try await model(services)
        await model.start(with: services)
        #expect(model.isReal)
        model.make()
        #expect(model.step == .consent)
        model.notNow()
        #expect(model.step == .ready)
        #expect(pipeline.prepared == 0 && pipeline.sent == 0)
        #expect(services.tryOnConsent.current() == nil)
    }

    @Test func allowKeepsHerConsentThenMakesThePictureAsAJob() async throws {
        let pipeline = StubPipeline()
        let services = services(pipeline)
        let model = try await model(services)
        await model.start(with: services)
        model.make()
        model.allow()
        #expect(services.tryOnConsent.current()?.version == TryOnConsent.currentVersion)
        await model.settle()
        // She could leave here; the job is the app's, not the sheet's.
        guard case .sending(let id) = model.step else {
            Issue.record("not sending: \(model.step)")
            return
        }
        let job = try #require(await services.aiJobs.finished(id))
        #expect(job.state == .done)
        await model.settle()
        let picture = try #require(job.picture)
        #expect(model.step == .made(picture))
        #expect(picture.isReal && picture.sent == StubPipeline.upload.sent)
        #expect(try await services.pictures.picture(picture.id) == picture)
        #expect(pipeline.prepared == 1 && pipeline.sent == 1)
        // The pieces sent were the look's own.
        let look = try await services.looks.look("o-blazer-office")
        #expect(!pipeline.pieces.isEmpty && pipeline.pieces == look.garmentIDs)
    }

    @Test func aPhotoThePhoneWontSendIsExplainedAndNothingIsSent() async throws {
        let pipeline = StubPipeline(refuse: .faceStillVisible)
        let services = services(pipeline, consent: TryOnConsent(agreedAt: TestTime.now))
        let model = try await model(services)
        await model.start(with: services)
        model.make()
        await model.settle()
        #expect(model.step == .refused(.faceStillVisible))
        #expect(pipeline.sent == 0)
        #expect(services.aiJobs.jobs.isEmpty)
    }

    @Test func leavingTheSheetLeavesTheJobRunning() async throws {
        let pipeline = StubPipeline(waits: true)
        let services = services(pipeline, consent: TryOnConsent(agreedAt: TestTime.now))
        let model = try await model(services)
        await model.start(with: services)
        model.make()
        await pipeline.waitForSend()
        model.leave()
        let job = try #require(services.aiJobs.jobs.first)
        #expect(job.state == .running)
        pipeline.open()
        let done = try #require(await services.aiJobs.finished(job.id))
        #expect(done.state == .done)
        // Opening Try it on again for the same look offers the picture she now has (FR-59).
        let again = try await self.model(services)
        await again.start(with: services)
        #expect(again.step == .alreadyMade(try #require(done.picture)))
    }
}

/// A pipeline that records what it was asked and answers at once (or refuses, or waits).
final class StubPipeline: TryOnPipeline, Sendable {
    private struct State {
        var prepared = 0
        var sent = 0
        var pieces: [Garment.ID] = []
        var gate: CheckedContinuation<Void, Never>?
        var isOpen = false
        var sendWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    private let refuse: TryOnPrepareProblem?
    private let waits: Bool

    static let upload = TryOnUpload(
        sent: TryOnSent(person: .stored("sent-person"), garments: []), work: nil,
        geometry: TryOnGeometry(width: 4, height: 4, face: [1, 1, 1, 1]), contextRevision: "rev_stub")

    init(refuse: TryOnPrepareProblem? = nil, waits: Bool = false) {
        self.refuse = refuse
        self.waits = waits
    }

    var prepared: Int { state.withLock { $0.prepared } }
    var sent: Int { state.withLock { $0.sent } }
    var pieces: [Garment.ID] { state.withLock { $0.pieces } }

    func prepare(photo: PhotoReference, pieces: [Garment]) async throws(TryOnPrepareProblem) -> TryOnUpload {
        state.withLock {
            $0.prepared += 1
            $0.pieces = pieces.map(\.id)
        }
        if let refuse { throw refuse }
        return Self.upload
    }

    func dress(_ upload: TryOnUpload, consentVersion: String, idempotencyKey: String)
        async throws(CloudLimitProblem) -> Data
    {
        let waiters = state.withLock { state in
            state.sent += 1
            defer { state.sendWaiters = [] }
            return state.sendWaiters
        }
        for waiter in waiters { waiter.resume() }
        if waits {
            await withCheckedContinuation { continuation in
                let now = state.withLock { state -> Bool in
                    if state.isOpen { return true }
                    state.gate = continuation
                    return false
                }
                if now { continuation.resume() }
            }
        }
        return Data([1])
    }

    func restore(_ dressed: Data, upload: TryOnUpload) async throws(TryOnError) -> PhotoReference {
        .stored("restored")
    }

    func discard(_ upload: TryOnUpload, keepingSent: Bool) async {}

    func waitForSend() async {
        if sent > 0 { return }
        await withCheckedContinuation { continuation in
            let already = state.withLock { state -> Bool in
                if state.sent > 0 { return true }
                state.sendWaiters.append(continuation)
                return false
            }
            if already { continuation.resume() }
        }
    }

    func open() {
        let gate = state.withLock { state in
            defer { state.gate = nil }
            state.isOpen = true
            return state.gate
        }
        gate?.resume()
    }
}
