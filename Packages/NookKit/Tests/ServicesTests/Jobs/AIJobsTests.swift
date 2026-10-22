import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// Background AI jobs (Phase 27c) on the real store: a job runs apart from any screen, keeps one
/// Idempotency-Key from its first try to its last, carries on after a relaunch, runs one at a
/// time, stops only for her Cancel, and says it's done with the banner, or a notification in the
/// background. Time only moves when a test moves the `ManualClock`.
@MainActor
struct AIJobsTests {
    static let demo = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)

    static func context(_ id: StyleRequest.ID = "req-1") -> StylingContext {
        StylingContext(
            request: StyleRequest(
                id: id, occasion: .office,
                weather: WeatherSnapshot(condition: .rain, temperatureCelsius: 14, observedAt: TestTime.now),
                createdAt: TestTime.now),
            eligibleGarments: demo.garments, now: TestTime.now, calendar: TestTime.calendar)
    }

    /// Fixture services with this stylist, and the job store on a real store file.
    static func services(_ stylist: some Stylist, threads: (any StylistThreadStore)? = nil) -> NookServices {
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        services.stylist = stylist
        if let threads { services.stylistThreads = threads }
        return services
    }

    let store: TemporaryStore
    let storage: NookStorage
    let clock = ManualClock()
    let notifier = RecordingNotifier()
    /// The date jobs see. Moved by `later(by:)`.
    let date = DateBox(TestTime.now)

    init() throws {
        store = try TemporaryStore("jobs")
        storage = try store.open()
    }

    func jobs(on storage: NookStorage? = nil, keys: [String] = ["idem_key_one_0000", "idem_key_two_0000"]) -> AIJobs {
        let keys = KeyBox(keys)
        let date = date
        return AIJobs(
            store: (storage ?? self.storage).aiJobs, notifier: notifier, clock: clock, now: { date.value },
            makeKey: { keys.next() }, pollEvery: .seconds(20), giveUpAfter: 600)
    }

    // MARK: Running

    @Test func aJobKeepsItsLooksInHerHistoryAndShowsTheBannerWhenSheIsElsewhere() async throws {
        let stylist = KeyedScript()
        let services = Self.services(stylist)
        let jobs = jobs()
        let before = try await services.looks.looks().count
        let job = try jobs.startStyling(Self.context(), services: services)
        let done = try #require(await jobs.finished(job.id))
        #expect(done.state == .done)
        #expect(done.outcome?.result?.versions.count == 3)
        #expect(try await services.looks.looks().count == before + 3)
        #expect(jobs.announcement == job.id)
        #expect(jobs.unseenResults(.styling) == 1)
        #expect(await stylist.keys == ["idem_key_one_0000"])
        // Opening it clears the banner and the dot, and withdraws any notification.
        jobs.markSeen(job.id)
        #expect(jobs.announcement == nil && jobs.unseenResults(.styling) == 0)
        await jobs.saved()
        #expect(try await storage.aiJobs.jobs().first?.isSeen == true)
    }

    @Test func noBannerForAResultSheIsAlreadyLookingAt() async throws {
        let stylist = KeyedScript([.wait])
        let jobs = jobs()
        let job = try jobs.startStyling(Self.context(), services: Self.services(stylist))
        jobs.showing(job.id)
        await stylist.waitForCall()
        await stylist.open()
        _ = await jobs.finished(job.id)
        #expect(jobs.announcement == nil)
        #expect(jobs.job(job.id)?.isSeen == true)
        #expect(jobs.unseenResults(.styling) == 0)
    }

    @Test func inTheBackgroundItPostsANotificationThatNamesNothingOfHers() async throws {
        let jobs = jobs()
        jobs.isInForeground = false
        let job = try jobs.startStyling(Self.context(), services: Self.services(KeyedScript()))
        _ = await jobs.finished(job.id)
        await notifier.waitForPosts(1)
        #expect(await notifier.posted == [.init(kind: .styling, id: job.id)])
        // The banner waits for her to come back to the app.
        #expect(jobs.announcement == job.id)
        // The words are fixed per kind; the job's ID is random.
        #expect(UUID(uuidString: job.id.rawValue) != nil)
    }

    /// She left the app with the result's screen open: the notification still goes, and the
    /// screen marks it seen when she's back.
    @Test func inTheBackgroundTheOpenScreenDoesNotStopTheNotification() async throws {
        let stylist = KeyedScript([.wait])
        let jobs = jobs()
        let job = try jobs.startStyling(Self.context(), services: Self.services(stylist))
        jobs.showing(job.id)
        await stylist.waitForCall()
        jobs.isInForeground = false
        await stylist.open()
        _ = await jobs.finished(job.id)
        await notifier.waitForPosts(1)
        #expect(await notifier.posted == [.init(kind: .styling, id: job.id)])
        #expect(jobs.announcement == nil)
        #expect(jobs.job(job.id)?.isSeen == false)
    }

    @Test func aLateAnswerIsAskedForAgainWithTheSameKeyUntilItComes() async throws {
        let stylist = KeyedScript([.fail(.timedOut), .fail(.limited(.busy(retryAfterSeconds: 2))), .looks])
        let jobs = jobs()
        let job = try jobs.startStyling(Self.context(), services: Self.services(stylist))
        await clock.waitForSleepers()
        #expect(jobs.job(job.id)?.state == .stillRunning)
        clock.advance(by: .seconds(20))
        await clock.waitForSleepers()
        clock.advance(by: .seconds(20))
        let done = try #require(await jobs.finished(job.id))
        #expect(done.state == .done)
        #expect(await stylist.keys == Array(repeating: "idem_key_one_0000", count: 3))
    }

    @Test func itStopsAskingAfterTenMinutesAndSaysItDidNotFinish() async throws {
        let stylist = KeyedScript([.fail(.timedOut), .fail(.timedOut)])
        let jobs = jobs()
        let job = try jobs.startStyling(Self.context(), services: Self.services(stylist))
        await clock.waitForSleepers()
        date.value = TestTime.now.addingTimeInterval(601)
        clock.advance(by: .seconds(20))
        let failed = try #require(await jobs.finished(job.id))
        #expect(failed.state == .failed && failed.failure == .notCompleted)
        #expect(await stylist.keys.count == 2)
        #expect(jobs.announcement == job.id)
    }

    @Test func oneJobRunsAtATimeAndTheNextWaitsItsTurn() async throws {
        let stylist = KeyedScript([.wait])
        let services = Self.services(stylist)
        let jobs = jobs()
        let first = try jobs.startStyling(Self.context("req-1"), services: services)
        let second = try jobs.startStyling(Self.context("req-2"), services: services)
        await stylist.waitForCall()
        #expect(jobs.job(second.id)?.state == .queued)
        // The same request again joins the job that's running.
        #expect(try jobs.startStyling(Self.context("req-1"), services: services).id == first.id)
        await stylist.open()
        #expect(await jobs.finished(second.id)?.state == .done)
        #expect(await stylist.keys == ["idem_key_one_0000", "idem_key_two_0000"])
    }

    @Test func onlyHerCancelStopsAJobAndThenTheNextOneRuns() async throws {
        let stylist = KeyedScript([.wait, .looks])
        let services = Self.services(stylist)
        let jobs = jobs()
        let first = try jobs.startStyling(Self.context("req-1"), services: services)
        let second = try jobs.startStyling(Self.context("req-2"), services: services)
        await stylist.waitForCall()
        // A screen coming and going changes nothing.
        jobs.showing(first.id)
        jobs.stoppedShowing(first.id)
        #expect(jobs.job(first.id)?.state == .running)
        jobs.cancel(first.id)
        #expect(jobs.job(first.id)?.state == .cancelled)
        #expect(await jobs.finished(second.id)?.state == .done)
        #expect(jobs.announcement == second.id)
    }

    @Test func noConsentMeansNoJobAndNothingKept() async throws {
        let jobs = jobs()
        #expect(throws: StylistError.needsConsent) {
            try jobs.startStyling(Self.context(), services: Self.services(KeyedScript(consent: false)))
        }
        #expect(jobs.jobs.isEmpty)
        await jobs.saved()
        #expect(try await storage.aiJobs.jobs().isEmpty)
    }

    @Test func aFailureIsSaidWithTheScreensWords() async throws {
        let jobs = jobs()
        let job = try jobs.startStyling(
            Self.context(),
            services: Self.services(KeyedScript([.fail(.limited(.paused(feature: .style, retryAfterSeconds: nil)))])))
        let failed = try #require(await jobs.finished(job.id))
        #expect(failed.failure == .limited(.paused(feature: .style, retryAfterSeconds: nil)))
        #expect(jobs.unseenResults(.styling) == 0)
    }

    // MARK: Relaunch

    @Test func aJobSentBeforeTheAppWasKilledIsAskedAgainWithItsKeyAfterARelaunch() async throws {
        let stylist = KeyedScript([.wait])
        let services = Self.services(stylist)
        let jobs = jobs()
        let job = try jobs.startStyling(Self.context(), services: services)
        await stylist.waitForCall()
        await jobs.saved()
        // The app is killed mid-job: the store says it was sent and is running.
        let kept = try #require(try await storage.aiJobs.jobs().first)
        #expect(kept.state == .running && kept.wasSent)

        let relaunched = try store.open()
        let answering = KeyedScript()
        let again = self.jobs(on: relaunched, keys: ["idem_new_key_00000"])
        await again.resume(with: Self.services(answering))
        let done = try #require(await again.finished(job.id))
        #expect(done.state == .done)
        // The same key, never a new one: the server answers from its record.
        #expect(await answering.keys == ["idem_key_one_0000"])
        #expect(again.announcement == job.id)
    }

    @Test func aJobNeverSentIsSentAfterARelaunchButNotIfSheAskedLongAgo() async throws {
        let waiting = AIJob(
            kind: .styling, idempotencyKey: "idem_queued_job_00",
            request: .styling(Self.context("req-1"), consentVersion: "stylist-1"),
            createdAt: TestTime.now)
        let old = AIJob(
            kind: .styling, idempotencyKey: "idem_old_job_0000",
            request: .styling(Self.context("req-2"), consentVersion: "stylist-1"),
            createdAt: TestTime.now.addingTimeInterval(-3600))
        try await storage.aiJobs.save(old)
        try await storage.aiJobs.save(waiting)
        let stylist = KeyedScript()
        let jobs = jobs()
        await jobs.resume(with: Self.services(stylist))
        #expect(await jobs.finished(waiting.id)?.state == .done)
        #expect(jobs.job(old.id)?.state == .failed)
        #expect(await stylist.keys == ["idem_queued_job_00"])
    }

    @Test func looksThatCouldNotBeKeptAreKeptAtTheNextForeground() async throws {
        var services = Self.services(KeyedScript())
        let looks = FailingLookStore(services.looks)
        services.looks = looks
        let jobs = jobs()
        let job = try jobs.startStyling(Self.context(), services: services)
        _ = await jobs.finished(job.id)
        #expect(jobs.job(job.id)?.isKept == false)
        looks.isLocked = false
        await jobs.resume(with: services)
        #expect(jobs.job(job.id)?.isKept == true)
        #expect(try await services.looks.looks().contains { $0.id == jobs.job(job.id)?.outcome?.result?.simple?.id })
    }

    @Test func finishedJobsGoAfterADay() async throws {
        let jobs = jobs()
        let job = try jobs.startStyling(Self.context(), services: Self.services(KeyedScript()))
        _ = await jobs.finished(job.id)
        await jobs.saved()
        date.value = TestTime.now.addingTimeInterval(25 * 3600)
        await jobs.resume(with: Self.services(KeyedScript()))
        #expect(jobs.jobs.isEmpty)
        #expect(try await storage.aiJobs.jobs().isEmpty)
    }

    @Test func deleteMyDataStopsEveryJobAndForgetsThem() async throws {
        let stylist = KeyedScript([.wait])
        let jobs = jobs()
        let job = try jobs.startStyling(Self.context(), services: Self.services(stylist))
        await stylist.waitForCall()
        try await AIJobsEraser(jobs).eraseAll()
        #expect(jobs.jobs.isEmpty)
        #expect(await jobs.finished(job.id) == nil)
        await jobs.saved()
        #expect(try await storage.aiJobs.jobs().isEmpty)
    }

    // MARK: The request a resumed job sends

    @Test func aKeptJobBuildsExactlyTheSameRequest() throws {
        var request = Self.context().request
        request.color = ColorWish(.olive, strength: .preferred)
        request.occasionNote = nil
        let context = StylingContext(
            request: request, eligibleGarments: Self.demo.garments, usualFit: .relaxed,
            recentCombinations: [[Self.demo.garments[0].id, Self.demo.garments[1].id]: TestTime.day(-2)],
            shownCombinations: [[Self.demo.garments[2].id]], now: TestTime.now, calendar: TestTime.calendar)
        let job = AIJob(
            kind: .styling, idempotencyKey: "idem_key_one_0000",
            request: .styling(context, consentVersion: "stylist-1"),
            createdAt: TestTime.now)
        let decoded = try JSONDecoder().decode(AIJob.self, from: JSONEncoder().encode(job))
        #expect(decoded == job)
        guard case .styling(let kept, let consent) = decoded.request else {
            Issue.record("Not a styling job")
            return
        }
        #expect(
            StyleCall.outfit(from: kept, consentVersion: consent)
                == StyleCall.outfit(from: context, consentVersion: "stylist-1"))
    }

    // MARK: Ask stylist

    @Test func aConversationKeepsHerQuestionAtOnceAndTheAnswerWhenItComes() async throws {
        let stylist = KeyedScript([.wait])
        let threads = storage.stylistThreads
        let services = Self.services(stylist, threads: threads)
        let jobs = jobs()
        let look = try #require(Self.demo.looks.first)
        let pieces = Self.demo.garments.filter { look.garmentIDs.contains($0.id) }
        let job = try await jobs.ask(
            "Can I wear this to a wedding?", about: look, pieces: pieces, in: nil, threads: threads, services: services)
        await stylist.waitForCall()
        let asked = try #require(try await threads.thread(about: look.id))
        #expect(asked.turns.map(\.from) == [.her])

        // She leaves; the app is killed; at the next launch the job carries on with its key.
        let relaunched = try store.open()
        let answering = KeyedScript()
        let again = self.jobs(on: relaunched)
        await again.resume(with: Self.services(answering, threads: relaunched.stylistThreads))
        #expect(await again.finished(job.id)?.state == .done)
        #expect(await answering.keys == ["idem_key_one_0000"])
        let answered = try #require(try await relaunched.stylistThreads.thread(asked.id))
        #expect(answered.turns.map(\.from) == [.her, .stylist])
        #expect(answered.turns.last?.pieces.allSatisfy { id in pieces.contains { $0.id == id } } == true)
    }
}

// MARK: Stand-ins

/// A keyed stylist that answers from a script and records every key it was sent.
actor KeyedScript: KeyedStylist {
    enum Reply: Sendable {
        case looks
        case fail(StylistError)
        /// Waits until the test opens it, then answers with looks.
        case wait
    }

    private var replies: [Reply]
    private let consents: Bool
    private(set) var keys: [String] = []
    private var isOpen = false
    private var openWaiters: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [CheckedContinuation<Void, Never>] = []

    init(_ replies: [Reply] = [], consent: Bool = true) {
        self.replies = replies
        consents = consent
    }

    nonisolated func consentVersion() throws(StylistError) -> String {
        guard consents else { throw .needsConsent }
        return "stylist-1"
    }

    func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome {
        try await style(context, consentVersion: "stylist-1", idempotencyKey: "unkeyed")
    }

    func style(_ context: StylingContext, consentVersion: String, idempotencyKey: String) async throws(StylistError)
        -> StyleOutcome
    {
        try await next(idempotencyKey)
        return try await MockStylist().style(context)
    }

    func ask(_ request: AskStylistRequest, idempotencyKey: String) async throws(StylistError) -> StylistReply {
        try await next(idempotencyKey)
        return StylistReply(text: "Yes, with the dressier shoes.", pieces: request.pieces.prefix(1).map(\.id))
    }

    private func next(_ key: String) async throws(StylistError) {
        keys.append(key)
        for waiter in callWaiters { waiter.resume() }
        callWaiters = []
        switch replies.isEmpty ? .looks : replies.removeFirst() {
        case .looks: return
        case .fail(let error): throw error
        case .wait:
            if !isOpen { await withCheckedContinuation { openWaiters.append($0) } }
            if Task.isCancelled { throw .cancelled }
        }
    }

    func waitForCall() async {
        if !keys.isEmpty { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in openWaiters { waiter.resume() }
        openWaiters = []
    }
}

/// Records what would have been posted.
actor RecordingNotifier: AIJobNotifier {
    struct Post: Equatable {
        let kind: AIJob.Kind
        let id: AIJob.ID
    }

    private(set) var posted: [Post] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func offer() async -> AIJobNotificationOffer { .allowed }
    func requestPermission() async -> Bool { true }
    func declineOffer() async {}
    func notifyDone(_ kind: AIJob.Kind, id: AIJob.ID) async {
        posted.append(Post(kind: kind, id: id))
        let ready = waiters.filter { $0.0 <= posted.count }
        waiters.removeAll { $0.0 <= posted.count }
        for waiter in ready { waiter.1.resume() }
    }
    func withdraw(_ id: AIJob.ID) async {}

    func waitForPosts(_ count: Int) async {
        if posted.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

/// A look store that fails while "locked", as the store does while the iPhone is locked.
final class FailingLookStore: LookStore, @unchecked Sendable {
    private let base: any LookStore
    private let lock = NSLock()
    private var locked = true

    init(_ base: any LookStore) {
        self.base = base
    }

    var isLocked: Bool {
        get { lock.withLock { locked } }
        set { lock.withLock { locked = newValue } }
    }

    func looks() async throws(StoreError) -> [Look] { try await base.looks() }
    func look(_ id: Look.ID) async throws(StoreError) -> Look { try await base.look(id) }
    func save(_ look: Look) async throws(StoreError) {
        if isLocked { throw .unavailable }
        try await base.save(look)
    }
    func update(_ id: Look.ID, _ change: @Sendable (inout Look) -> Void) async throws(StoreError) -> Look {
        try await base.update(id, change)
    }
    func delete(_ id: Look.ID) async throws(StoreError) { try await base.delete(id) }
    func recordWear(of id: Look.ID, on date: Date) async throws(StoreError) {
        try await base.recordWear(of: id, on: date)
    }
    func removeWear(of id: Look.ID, on date: Date) async throws(StoreError) {
        try await base.removeWear(of: id, on: date)
    }
    func eraseAll() async throws(StoreError) { try await base.eraseAll() }
}

/// A date the test moves, read by the jobs from any isolation.
final class DateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var value: Date {
        get { lock.withLock { date } }
        set { lock.withLock { date = newValue } }
    }
}

/// Hands out keys in order.
final class KeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String]

    init(_ keys: [String]) {
        self.keys = keys
    }

    func next() -> String {
        lock.withLock { keys.isEmpty ? IdempotencyKey.make() : keys.removeFirst() }
    }
}
