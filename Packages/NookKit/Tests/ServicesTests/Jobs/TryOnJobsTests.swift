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

    /// 33c: the loading screen's captions come from the job's real step, kept on the job.
    @Test func aRunningJobKnowsWhichStepItIsOn() async throws {
        let pipeline = ScriptedTryOn([.wait])
        let jobs = jobs()
        let job = jobs.startTryOn(Self.request, services: services(pipeline))
        // Waiting for nothing: it starts at once, and the request is out, being dressed.
        await pipeline.waitForCall()
        let running = try #require(jobs.job(job.id))
        #expect(running.tryOnStage == .dressing)
        let progress = try #require(TryOnProgress(job: running))
        #expect(progress.mark(for: .checkingFace) == .done && progress.mark(for: .dressing) == .doing)
        #expect(progress.mark(for: .restoring) == .todo)
        await pipeline.open()
        let done = try #require(await jobs.finished(job.id))
        let finished = try #require(TryOnProgress(job: done))
        #expect(TryOnStage.allCases.allSatisfy { finished.mark(for: $0) == .done })
        await jobs.saved()
    }

    @Test func aFailureStopsAtTheStepThatFailed() async throws {
        // The image service says no: it stopped at dressing, and nothing later was done.
        let refused = ScriptedTryOn([.fail(.didNotFinish(retryAfterSeconds: nil))])
        let first = jobs()
        let job = first.startTryOn(Self.request, services: services(refused))
        let failed = try #require(await first.finished(job.id))
        #expect(failed.tryOnStage == .dressing)
        let atDressing = try #require(TryOnProgress(job: failed))
        #expect(atDressing.mark(for: .dressing) == .stopped && atDressing.mark(for: .restoring) == .todo)
        #expect(atDressing.mark(for: .hidingFace) == .done)
        await first.saved()

        // The picture came back but her head couldn't be put back on: it stopped at restoring.
        let broken = ScriptedTryOn([.failToRestore])
        let second = jobs()
        let other = second.startTryOn(Self.request, services: services(broken))
        let lost = try #require(await second.finished(other.id))
        #expect(lost.state == .failed && lost.tryOnStage == .restoring)
        let atRestoring = try #require(TryOnProgress(job: lost))
        #expect(atRestoring.mark(for: .dressing) == .done && atRestoring.mark(for: .restoring) == .stopped)
        await second.saved()
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

    // MARK: 35: following the action by its ID

    static let actionID = "act_" + String(repeating: "a", count: 32)

    @Test func aLateAnswerKeepsTheActionIDAndTheNextAskStartsFromIt() async throws {
        let pipeline = ScriptedTryOn([.startedThenFail(Self.actionID, .busy(retryAfterSeconds: 5)), .picture])
        let jobs = jobs()
        let job = jobs.startTryOn(Self.request, services: services(pipeline))
        // Still running: the server named the action, so the job kept its ID.
        await clock.waitForSleepers(1)
        await jobs.saved()
        #expect(jobs.job(job.id)?.state == .stillRunning)
        #expect(jobs.job(job.id)?.actionID == Self.actionID)
        clock.advance(by: .seconds(20))
        let done = try #require(await jobs.finished(job.id))
        #expect(done.state == .done)
        // The second ask carried the ID to resume from, and the same key.
        #expect(await pipeline.resumes == [nil, Self.actionID])
        #expect(await pipeline.keys == ["idem_tryon_one_0000", "idem_tryon_one_0000"])
        await jobs.saved()
    }

    @Test func afterARelaunchTheStoredActionIDIsHandedBackToResumeFrom() async throws {
        let first = ScriptedTryOn([.startedThenWait(Self.actionID)])
        let running = jobs()
        let job = running.startTryOn(Self.request, services: services(first))
        await first.waitForCall()
        // The ID reaches the job through the main actor; wait until the store holds it.
        while running.job(job.id)?.actionID == nil { await Task.yield() }
        await running.saved()
        let kept = try #require(try await storage.aiJobs.jobs().first)
        #expect(kept.actionID == Self.actionID)

        // Killed here. The relaunched app finds the job with its ID and asks for the status.
        let second = ScriptedTryOn([.picture])
        let relaunched = jobs(on: try store.open())
        await relaunched.resume(with: services(second))
        let done = try #require(await relaunched.finished(job.id))
        #expect(done.state == .done)
        #expect(await second.resumes == [Self.actionID])
        #expect(await second.keys == ["idem_tryon_one_0000"])
        await first.open()
        await relaunched.saved()
        await running.saved()
    }

    @Test func aJobKeptBeforeThisChangeHasNoActionIDAndStillLoads() async throws {
        let pipeline = ScriptedTryOn([.picture])
        let jobs = jobs()
        let job = jobs.startTryOn(Self.request, services: services(pipeline))
        _ = await jobs.finished(job.id)
        await jobs.saved()
        let kept = try #require(try await storage.aiJobs.jobs().first)
        // An older record has no such field: it decodes with none.
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(kept)) as? [String: Any])
        object["actionID"] = nil
        let older = try JSONDecoder().decode(AIJob.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.actionID == nil && older.id == kept.id)
    }
}

/// A try-on pipeline that answers as scripted and records keys and discards.
actor ScriptedTryOn: TryOnPipeline {
    enum Step {
        case picture
        case fail(CloudLimitProblem)
        /// Waits until `open()`, then gives the picture.
        case wait
        /// 35: the server names the action (`link.started`), then it fails like `fail`.
        case startedThenFail(String, CloudLimitProblem)
        /// 35: the server names the action, then it waits until `open()` and gives the picture.
        case startedThenWait(String)
        /// 33c: dresses her, then the phone can't put her head back on.
        case failToRestore
    }

    struct Discard: Equatable {
        let work: Bool
        let sent: Bool
    }

    private var steps: [Step]
    private(set) var keys: [String] = []
    /// 35: the action ID each call was given to resume with, in order (nil for a first send).
    private(set) var resumes: [String?] = []
    private var failsRestore = false
    private(set) var discarded: [Discard] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var discardWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    nonisolated func prepare(
        photo: PhotoReference, pieces: [Garment], progress: @escaping @MainActor @Sendable (TryOnStage) -> Void
    ) async throws(TryOnPrepareProblem) -> TryOnUpload { TryOnJobsTests.upload }

    func dress(_ upload: TryOnUpload, consentVersion: String, idempotencyKey: String)
        async throws(CloudLimitProblem) -> Data
    {
        try await dress(upload, consentVersion: consentVersion, idempotencyKey: idempotencyKey, link: .none)
    }

    func dress(_ upload: TryOnUpload, consentVersion: String, idempotencyKey: String, link: ActionLink)
        async throws(CloudLimitProblem) -> Data
    {
        keys.append(idempotencyKey)
        resumes.append(link.resume)
        for waiter in callWaiters { waiter.resume() }
        callWaiters = []
        let step = steps.isEmpty ? .picture : steps.removeFirst()
        failsRestore = false
        switch step {
        case .failToRestore:
            failsRestore = true
            return Data([1])
        case .picture: return Data([1])
        case .fail(let problem): throw problem
        case .wait:
            await withCheckedContinuation { gate = $0 }
            return Data([1])
        case .startedThenFail(let id, let problem):
            link.started(id)
            throw problem
        case .startedThenWait(let id):
            link.started(id)
            await withCheckedContinuation { gate = $0 }
            return Data([1])
        }
    }

    func restore(_ dressed: Data, upload: TryOnUpload) async throws(TryOnError) -> PhotoReference {
        if failsRestore { throw .notCompleted }
        return .stored("restored")
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
