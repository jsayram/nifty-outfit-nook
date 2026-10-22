import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// 33a: a try-on picture as a background job (27c), on the real store, with time moved only by
/// the `ManualClock`: one key from the first try to the last, the picture kept in Pictures with
/// what was sent, the work files let go, the banner, Cancel, and carrying on after a relaunch.
@MainActor
struct TryOnJobsTests {
    let store: TemporaryStore
    let storage: NookStorage
    let clock = ManualClock()
    let notifier = RecordingNotifier()
    let date = DateBox(TestTime.now)

    init() throws {
        store = try TemporaryStore("tryon-jobs")
        storage = try store.open()
    }

    func jobs(on storage: NookStorage? = nil) -> AIJobs {
        let keys = KeyBox(["idem_tryon_one_0000", "idem_tryon_two_0000"])
        let date = date
        return AIJobs(
            store: (storage ?? self.storage).aiJobs, notifier: notifier, clock: clock, now: { date.value },
            makeKey: { keys.next() }, pollEvery: .seconds(20), giveUpAfter: 600)
    }

    func services(_ pipeline: ScriptedTryOn) -> NookServices {
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        services.tryOnPipeline = pipeline
        services.pictures = storage.pictures
        return services
    }

    nonisolated static let look = Look(
        id: "l-tryon", pieces: [LookPiece(id: "p1", content: .garment("g-1"))], name: "Sweater", isSaved: true,
        createdAt: TestTime.now)

    nonisolated static let upload = TryOnUpload(
        sent: TryOnSent(
            person: .stored("sent-person"),
            garments: [SentGarment(garmentID: "g-1", category: .top, subKind: .sweater, image: .stored("sent-g1"))]),
        work: TryOnWorkFiles(studio: .stored("work-studio"), matte: .stored("work-matte"), head: .stored("work-head")),
        geometry: TryOnGeometry(width: 10, height: 10, face: [1, 1, 2, 2]), contextRevision: "rev_test")

    nonisolated static let request = TryOnJobRequest(look: look, upload: upload, consentVersion: "tryon-1")

    @Test func aTryOnJobKeepsOneKeyAndItsPictureWithWhatWasSent() async throws {
        let pipeline = ScriptedTryOn([.fail(.account(.timedOut)), .picture])
        let jobs = jobs()
        let job = jobs.startTryOn(Self.request, services: services(pipeline))
        // The answer was late: the job waits on the clock, then asks again with the same key.
        await clock.waitForSleepers(1)
        #expect(jobs.job(job.id)?.state == .stillRunning)
        clock.advance(by: .seconds(20))
        let done = try #require(await jobs.finished(job.id))
        #expect(done.state == .done)
        #expect(await pipeline.keys == ["idem_tryon_one_0000", "idem_tryon_one_0000"])
        let picture = try #require(done.picture)
        #expect(picture.sent == Self.upload.sent)
        #expect(picture.image == .generated(.stored("restored")))
        #expect(picture.lookID == Self.look.id)
        #expect(try await storage.pictures.pictures().map(\.id) == [picture.id])
        // The work files go once the picture is kept; what was sent stays with it.
        await pipeline.waitForDiscards(1)
        #expect(await pipeline.discarded == [.init(work: true, sent: false)])
        #expect(jobs.job(job.id).flatMap { if case .tryOn(let r) = $0.request { r.upload.work } else { nil } } == nil)
        // The banner says so, and a dot shows on Saved Looks until she opens it.
        #expect(jobs.announcement == job.id)
        #expect(jobs.unseenResults(.tryOn) == 1)
        jobs.markPictureSeen(picture.id)
        #expect(jobs.unseenResults(.tryOn) == 0 && jobs.announcement == nil)
        await jobs.saved()
    }

    @Test func aFailedTryOnLetsGoOfEveryFile() async throws {
        let pipeline = ScriptedTryOn([.fail(.didNotFinish(retryAfterSeconds: nil))])
        let jobs = jobs()
        let job = jobs.startTryOn(Self.request, services: services(pipeline))
        let failed = try #require(await jobs.finished(job.id))
        #expect(failed.state == .failed && failed.failure == .notCompleted)
        await pipeline.waitForDiscards(1)
        #expect(await pipeline.discarded == [.init(work: true, sent: true)])
        #expect(try await storage.pictures.pictures().isEmpty)
        await jobs.saved()
    }

    @Test func herCancelStopsItAndLetsGoOfTheFiles() async throws {
        let pipeline = ScriptedTryOn([.wait])
        let jobs = jobs()
        let job = jobs.startTryOn(Self.request, services: services(pipeline))
        await pipeline.waitForCall()
        jobs.cancel(job.id)
        #expect(jobs.job(job.id)?.state == .cancelled)
        await pipeline.waitForDiscards(1)
        #expect(await pipeline.discarded == [.init(work: true, sent: true)])
        await pipeline.open()
        await jobs.saved()
    }

    @Test func afterARelaunchTheSameKeyIsAskedAgainAndTheFilesAreKeptMeanwhile() async throws {
        let first = ScriptedTryOn([.wait])
        let running = jobs()
        let job = running.startTryOn(Self.request, services: services(first))
        await first.waitForCall()
        await running.saved()
        // The app is killed here. The kept job still points to its files, so the launch sweep
        // keeps them (`StoredImageFiles.referencedIDs`), and a new launch asks again.
        let keptJobs = try await storage.aiJobs.jobs()
        let kept = try #require(keptJobs.first)
        #expect(kept.wasSent && kept.state == .running)
        let second = ScriptedTryOn([.picture])
        let relaunched = jobs(on: try store.open())
        await relaunched.resume(with: services(second))
        let done = try #require(await relaunched.finished(job.id))
        #expect(done.state == .done)
        #expect(await second.keys == ["idem_tryon_one_0000"])
        await first.open()
        await relaunched.saved()
        await running.saved()
    }
}

/// A try-on pipeline that answers as scripted and records keys and discards.
actor ScriptedTryOn: TryOnPipeline {
    enum Step {
        case picture
        case fail(CloudLimitProblem)
        /// Waits until `open()`, then gives the picture.
        case wait
    }

    struct Discard: Equatable {
        let work: Bool
        let sent: Bool
    }

    private var steps: [Step]
    private(set) var keys: [String] = []
    private(set) var discarded: [Discard] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var discardWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    nonisolated func prepare(photo: PhotoReference, pieces: [Garment]) async throws(TryOnPrepareProblem)
        -> TryOnUpload
    { TryOnJobsTests.upload }

    func dress(_ upload: TryOnUpload, consentVersion: String, idempotencyKey: String)
        async throws(CloudLimitProblem) -> Data
    {
        keys.append(idempotencyKey)
        for waiter in callWaiters { waiter.resume() }
        callWaiters = []
        let step = steps.isEmpty ? .picture : steps.removeFirst()
        switch step {
        case .picture: return Data([1])
        case .fail(let problem): throw problem
        case .wait:
            await withCheckedContinuation { gate = $0 }
            return Data([1])
        }
    }

    func restore(_ dressed: Data, upload: TryOnUpload) async throws(TryOnError) -> PhotoReference {
        .stored("restored")
    }

    func discard(_ upload: TryOnUpload, keepingSent: Bool) async {
        discarded.append(Discard(work: upload.work != nil, sent: !keepingSent))
        let ready = discardWaiters.filter { $0.0 <= discarded.count }
        discardWaiters.removeAll { $0.0 <= discarded.count }
        for waiter in ready { waiter.1.resume() }
    }

    func waitForCall() async {
        if !keys.isEmpty { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }

    func waitForDiscards(_ count: Int) async {
        if discarded.count >= count { return }
        await withCheckedContinuation { discardWaiters.append((count, $0)) }
    }

    func open() {
        gate?.resume()
        gate = nil
    }
}
