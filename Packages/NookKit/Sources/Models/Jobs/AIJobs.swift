import Foundation
import Observation

/// Whether to offer her a note when a long job finishes (Phase 27c).
public enum AIJobNotificationOffer: Sendable, Equatable {
    /// Not asked yet: the app explains first, then iOS asks.
    case offer
    /// She said yes.
    case allowed
    /// She said no (to the app or to iOS), or iOS can't ask. The banner in the app still works.
    case off
}

/// How the app tells her a job finished while it was in the background: a local notification
/// (Phase 27c). The text never names a piece, a look or anything she wrote.
public protocol AIJobNotifier: Sendable {
    func offer() async -> AIJobNotificationOffer
    /// Asks iOS for permission (its own alert). Only after the app's explanation, never at launch.
    @discardableResult func requestPermission() async -> Bool
    /// She said Not now to the app's explanation: it isn't offered again.
    func declineOffer() async
    /// Posts "your … is ready" for this kind of job now. Does nothing without permission.
    func notifyDone(_ kind: AIJob.Kind, id: AIJob.ID) async
    /// Removes a delivered note she no longer needs (she opened the result in the app).
    func withdraw(_ id: AIJob.ID) async
}

/// No notifications: previews, tests and the sample closet.
public struct NoAIJobNotifier: AIJobNotifier {
    public init() {}
    public func offer() async -> AIJobNotificationOffer { .off }
    public func requestPermission() async -> Bool { false }
    public func declineOffer() async {}
    public func notifyDone(_ kind: AIJob.Kind, id: AIJob.ID) async {}
    public func withdraw(_ id: AIJob.ID) async {}
}

/// The app-level owner of every paid AI job (Phase 27c, from 27a's `StylingJobs`; Jose, 21
/// October 2026). A job keeps going while she browses, searches or opens other tabs; only her
/// Cancel stops it. It's kept in the store, so after a relaunch it carries on: a job that was
/// sent is asked again with the same Idempotency-Key, and the server answers from its record
/// without running or charging it again. Results land in her history whether or not a screen
/// waits for them, then the app tells her: a banner and a dot in the app, or a local notification
/// when the app is in the background.
///
/// One job runs at a time, like the server's "one paid action at a time per account"; the rest
/// wait as `queued`. A job whose answer didn't come back in time is `stillRunning` and asks again
/// every `pollEvery` until it's done, or until `giveUpAfter` has passed since she asked.
@MainActor
@Observable
public final class AIJobs {
    /// Every job this iPhone knows, oldest first. Finished ones go after `keepFinishedFor`.
    public private(set) var jobs: [AIJob] = []
    /// The finished job the banner is about, if any.
    public private(set) var announcement: AIJob.ID?
    /// False while the app is in the background: a finished job then posts a notification
    /// instead of the banner. The app sets it from the scene phase.
    public var isInForeground = true

    @ObservationIgnored private let store: any AIJobStore
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let makeKey: @Sendable () -> String
    @ObservationIgnored public var notifier: any AIJobNotifier
    @ObservationIgnored private let pollEvery: Duration
    @ObservationIgnored private let giveUpAfter: TimeInterval
    @ObservationIgnored private let keepFinishedFor: TimeInterval
    @ObservationIgnored private var services: NookServices?
    @ObservationIgnored private var tasks: [AIJob.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var waiters: [AIJob.ID: [CheckedContinuation<AIJob?, Never>]] = [:]
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var onScreen: [AIJob.ID: Int] = [:]
    @ObservationIgnored private var loaded = false

    /// - Parameters:
    ///   - clock: what the waits between asks are counted on. The app uses `ContinuousClock`;
    ///     tests pass one they move by hand.
    ///   - now: the date on jobs, and what `giveUpAfter` and `keepFinishedFor` are measured with.
    ///   - pollEvery: how long a `stillRunning` job waits before asking again.
    ///   - giveUpAfter: how long after she asked a job stops asking and says it didn't finish. The
    ///     server's own record of an action outlives it; a later ask would still be free.
    ///   - keepFinishedFor: how long a finished job stays, so its banner, dot and result survive
    ///     a relaunch. Its looks stay in her history for good.
    public nonisolated init(
        store: any AIJobStore = InMemoryAIJobStore(), notifier: any AIJobNotifier = NoAIJobNotifier(),
        clock: any Clock<Duration> = ContinuousClock(), now: @escaping @Sendable () -> Date = { .now },
        makeKey: @escaping @Sendable () -> String = { IdempotencyKey.make() }, pollEvery: Duration = .seconds(20),
        giveUpAfter: TimeInterval = 10 * 60, keepFinishedFor: TimeInterval = 24 * 60 * 60
    ) {
        self.store = store
        self.notifier = notifier
        self.clock = clock
        self.now = now
        self.makeKey = makeKey
        self.pollEvery = pollEvery
        self.giveUpAfter = giveUpAfter
        self.keepFinishedFor = keepFinishedFor
    }

    // MARK: Reading

    public func job(_ id: AIJob.ID) -> AIJob? { jobs.first { $0.id == id } }

    /// The newest job for this Style Me request.
    public func job(forStyleRequest id: StyleRequest.ID) -> AIJob? {
        jobs.last { $0.styleRequestID == id }
    }

    /// 33a: the newest try-on job for this look.
    public func job(forTryOnOf lookID: Look.ID) -> AIJob? {
        jobs.last { $0.tryOnLookID == lookID }
    }

    /// Jobs not finished yet.
    public var activeJobs: [AIJob] { jobs.filter { $0.state.isActive } }

    /// Finished results she hasn't seen, of this kind: the dot on the tab.
    public func unseenResults(_ kind: AIJob.Kind) -> Int {
        jobs.count { $0.kind == kind && $0.state == .done && !$0.isSeen }
    }

    // MARK: Starting and stopping

    /// Starts a Style Me request as a job, or gives back the one already running for it. Throws
    /// `needsConsent` before anything is kept or sent.
    @discardableResult
    public func startStyling(_ context: StylingContext, services: NookServices) throws(StylistError) -> AIJob {
        self.services = services
        if let existing = job(forStyleRequest: context.request.id), existing.state.isActive { return existing }
        let consent = try (services.stylist as? any KeyedStylist)?.consentVersion() ?? ""
        return add(
            AIJob(
                kind: .styling, idempotencyKey: makeKey(), request: .styling(context, consentVersion: consent),
                createdAt: now()))
    }

    /// Asks the stylist a question about a look, in its conversation. Her turn is kept in the
    /// thread at once; the stylist's answer is added when the job is done, wherever she is.
    @discardableResult
    public func ask(
        _ text: String, about look: Look, pieces: [Garment], in threadID: StylistThread.ID?,
        threads: any StylistThreadStore, services: NookServices
    ) async throws(StylistError) -> AIJob {
        self.services = services
        guard let stylist = services.stylist as? any KeyedStylist else { throw .notCompleted }
        let consent = try stylist.consentVersion()
        var thread: StylistThread
        do {
            var found: StylistThread?
            if let threadID { found = try await threads.thread(threadID) }
            thread = found ?? StylistThread(lookID: look.id, createdAt: now())
            let earlier = thread.turns
            let turn = StylistThread.Turn(from: .her, text: text, at: now())
            thread.append(turn)
            try await threads.save(thread)
            let request = AskStylistRequest(
                thread: thread.id, turn: turn.id, text: text, look: look, pieces: pieces, earlier: earlier,
                consentVersion: consent)
            return add(
                AIJob(kind: .askStylist, idempotencyKey: makeKey(), request: .ask(request), createdAt: now()))
        } catch {
            throw .notCompleted
        }
    }

    /// 33a: starts a try-on picture as a job, or gives back the one already running for this look.
    /// The upload was prepared and checked on the phone first; nothing else is sent.
    @discardableResult
    public func startTryOn(_ request: TryOnJobRequest, services: NookServices) -> AIJob {
        self.services = services
        if let existing = job(forTryOnOf: request.look.id), existing.state.isActive { return existing }
        return add(AIJob(kind: .tryOn, idempotencyKey: makeKey(), request: .tryOn(request), createdAt: now()))
    }

    /// Her Cancel. The server may still finish an action it already started; it's never run twice.
    public func cancel(_ id: AIJob.ID) {
        guard let job = job(id), job.state.isActive else { return }
        tasks[id]?.cancel()
        tasks[id] = nil
        update(id) {
            $0.state = .cancelled
            $0.finishedAt = now()
        }
        letGoOfUpload(id, keepingSent: false)
        finishWaiters(id)
        runNext()
    }

    /// Waits until the job is done, failed or cancelled, and gives it back (`nil` if Delete my
    /// data erased it meanwhile).
    public func finished(_ id: AIJob.ID) async -> AIJob? {
        guard let job = job(id) else { return nil }
        if !job.state.isActive { return job }
        return await withCheckedContinuation { waiters[id, default: []].append($0) }
    }

    /// Waits until no job is running or waiting, for the app's background task.
    public func idle() async {
        if activeJobs.isEmpty { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    // MARK: Screens

    /// A screen shows this job's result (or waits for it), so it needs no banner or dot.
    public func showing(_ id: AIJob.ID) {
        onScreen[id, default: 0] += 1
        if job(id)?.state == .done { markSeen(id) }
    }

    public func stoppedShowing(_ id: AIJob.ID) {
        let count = onScreen[id] ?? 0
        onScreen[id] = count > 1 ? count - 1 : nil
    }

    /// She opened the result.
    public func markSeen(_ id: AIJob.ID) {
        if announcement == id { announcement = nil }
        guard let job = job(id), !job.isSeen else { return }
        update(id) { $0.isSeen = true }
        Task { await notifier.withdraw(id) }
    }

    /// 33a: she opened this try-on picture, wherever from: its job needs no banner or dot.
    public func markPictureSeen(_ id: TryOnPicture.ID) {
        for job in jobs where job.picture?.id == id { markSeen(job.id) }
    }

    /// A job whose result she asked to open from outside the screens (a notification she tapped).
    /// The tab bar opens it and calls `didOpen`.
    public private(set) var openRequest: AIJob.ID?

    public func requestOpen(_ id: AIJob.ID) {
        openRequest = id
    }

    public func didOpen() {
        openRequest = nil
    }

    /// She closed the banner without opening it. The dot stays until she sees the result.
    public func dismissAnnouncement() {
        announcement = nil
    }

    // MARK: Launch and foreground

    /// Reads the kept jobs (once), tidies away old finished ones, and carries on with the rest:
    /// one that was sent is asked again with its key; one that wasn't is sent now, unless she
    /// asked more than `giveUpAfter` ago, when it says it didn't finish. Results that couldn't be
    /// kept are written again. The app calls it at launch and each time it comes back to the
    /// foreground.
    public func resume(with services: NookServices) async {
        self.services = services
        if !loaded {
            loaded = true
            let kept = (try? await store.jobs()) ?? []
            let known = Set(jobs.map(\.id))
            jobs = (jobs + kept.filter { !known.contains($0.id) }).sorted { $0.createdAt < $1.createdAt }
        }
        let date = now()
        let old = jobs.filter {
            !$0.state.isActive && date.timeIntervalSince($0.finishedAt ?? $0.createdAt) > keepFinishedFor
        }
        if !old.isEmpty {
            jobs.removeAll { job in old.contains { $0.id == job.id } }
            try? await store.remove(old.map(\.id))
        }
        for job in jobs where job.state.isActive && tasks[job.id] == nil {
            if job.wasSent {
                // Asked again once, with its key, however long ago: the server answers a finished
                // action from its record for free. If it still has no answer and `giveUpAfter`
                // has passed, the job then says it didn't finish.
                continue
            } else if date.timeIntervalSince(job.createdAt) > giveUpAfter {
                // Never sent, and she asked a while ago: not sent now, so nothing she asked for
                // long ago is charged by surprise (Phase 26's "nothing queued while offline").
                finish(job.id, .failed, failure: .notCompleted)
                letGoOfUpload(job.id, keepingSent: false)
            } else if job.state != .queued {
                update(job.id) { $0.state = .queued }
            }
        }
        for job in jobs where job.state == .done && !job.isKept {
            await keep(job.id)
        }
        runNext()
    }

    /// Delete my data: stops every job and forgets them.
    public func eraseAll() async throws(StoreError) {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        let ids = jobs.map(\.id)
        jobs = []
        announcement = nil
        for id in ids { finishWaiters(id) }
        finishIdleWaiters()
        try await store.eraseAll()
    }

    // MARK: Running

    private func add(_ job: AIJob) -> AIJob {
        jobs.append(job)
        persist(job)
        runNext()
        return self.job(job.id) ?? job
    }

    /// Starts the oldest waiting job when nothing else is running.
    private func runNext() {
        guard tasks.isEmpty else { return }
        guard let next = jobs.first(where: { $0.state.isActive }) else {
            finishIdleWaiters()
            return
        }
        let id = next.id
        tasks[id] = Task { [weak self] in await self?.drive(id) }
    }

    private enum Attempt {
        case done(AIJob.Result)
        case stillRunning
        case failed(AIJob.Failure)
        case stopped
    }

    private func drive(_ id: AIJob.ID) async {
        while let job = job(id), job.state.isActive, !Task.isCancelled {
            let sentBefore = job.wasSent
            update(id) {
                if $0.state == .queued { $0.state = .running }
                $0.wasSent = true
            }
            let attempt = await perform(job, sentBefore: sentBefore)
            guard !Task.isCancelled, self.job(id)?.state.isActive == true else { return }
            switch attempt {
            case .done(let result):
                // Her history first, so whoever waits for the job finds the looks there.
                update(id) { $0.result = result }
                await keep(id)
                guard self.job(id)?.state.isActive == true else { return }
                finish(id, .done, result: result)
                announce(id)
            case .failed(let failure):
                finish(id, .failed, failure: failure)
                letGoOfUpload(id, keepingSent: false)
                announce(id)
            case .stopped:
                return
            case .stillRunning:
                if now().timeIntervalSince(job.createdAt) > giveUpAfter {
                    finish(id, .failed, failure: .notCompleted)
                    letGoOfUpload(id, keepingSent: false)
                    announce(id)
                } else {
                    update(id) { $0.state = .stillRunning }
                    guard (try? await clock.sleep(for: pollEvery)) != nil else { return }
                    continue
                }
            }
            break
        }
        // A cancelled task leaves `tasks` to whoever cancelled it.
        if tasks[id] != nil, job(id)?.state.isActive != true {
            tasks[id] = nil
            runNext()
        }
    }

    private func perform(_ job: AIJob, sentBefore: Bool) async -> Attempt {
        guard let services else { return .failed(.notCompleted) }
        do throws(StylistError) {
            switch job.request {
            case .styling(let context, let consent):
                let outcome: StyleOutcome
                if let keyed = services.stylist as? any KeyedStylist {
                    outcome = try await keyed.style(
                        context, consentVersion: consent, idempotencyKey: job.idempotencyKey)
                } else {
                    // Stage A's stylist and test stand-ins: nothing paid, so no key to keep.
                    outcome = try await services.stylist.style(context)
                }
                if let result = outcome.result, !ResultCheck.problems(in: result, for: context).isEmpty {
                    return .failed(.notCompleted)
                }
                return .done(.styling(outcome))
            case .ask(let request):
                guard let keyed = services.stylist as? any KeyedStylist else { return .failed(.notCompleted) }
                let reply = try await keyed.ask(request, idempotencyKey: job.idempotencyKey)
                let turn = StylistThread.Turn(from: .stylist, text: reply.text, pieces: reply.pieces, at: now())
                do {
                    var thread =
                        try await services.stylistThreads.thread(request.thread)
                        ?? StylistThread(id: request.thread, lookID: request.look.id, createdAt: job.createdAt)
                    thread.append(turn)
                    try await services.stylistThreads.save(thread)
                } catch {
                    return .failed(.notCompleted)
                }
                return .done(.answer(thread: request.thread, turn: turn.id))
            case .tryOn(let request):
                guard let pipeline = services.tryOnPipeline else { return .failed(.notCompleted) }
                let dressed: Data
                do {
                    // 35: the photos go up once. The server's action ID is kept with the job as soon as
                    // it is known, so a late answer or a relaunch asks for its status, not for a resend.
                    let id = job.id
                    let link = ActionLink(resume: job.actionID) { [weak self] actionID in
                        Task { @MainActor in self?.update(id) { $0.actionID = actionID } }
                    }
                    dressed = try await pipeline.dress(
                        request.upload, consentVersion: request.consentVersion, idempotencyKey: job.idempotencyKey,
                        link: link)
                } catch {
                    throw CloudStylist.error(for: error)
                }
                // Her head goes back on the phone. The picture keeps exactly what was sent.
                let image: PhotoReference
                do {
                    image = try await pipeline.restore(dressed, upload: request.upload)
                } catch {
                    return Task.isCancelled ? .stopped : .failed(.notCompleted)
                }
                let picture = TryOnPicture(
                    id: .random(), of: request.look, image: .generated(image), createdAt: now(),
                    sent: request.upload.sent)
                return .done(.tryOn(picture))
            }
        } catch {
            switch error {
            case .timedOut, .limited(.busy): return .stillRunning
            // Sent before (a relaunch, or the connection dropped after sending): ask again later.
            case .offline: return sentBefore ? .stillRunning : .failed(.offline)
            case .cancelled: return Task.isCancelled ? .stopped : .failed(.notCompleted)
            case .notCompleted: return .failed(.notCompleted)
            case .needsConsent: return .failed(.needsConsent)
            case .invalidRequest: return .failed(.requestChanged)
            case .limited(let problem): return .failed(.limited(problem))
            }
        }
    }

    /// Writes a styling job's looks to her history and marks its suitcase used, once. If the store
    /// can't be written (the iPhone is locked), the job remembers and the next `resume` tries again.
    private func keep(_ id: AIJob.ID) async {
        guard let services, let job = job(id) else { return }
        if case .tryOn = job.request {
            await keepPicture(id, services: services)
            return
        }
        guard case .styling(let context, _) = job.request, let outcome = job.outcome else { return }
        var kept = true
        if let result = outcome.result, !result.notes.contains(.fromHistory) {
            for look in result.versions {
                do { try await services.looks.save(look) } catch { kept = false }
            }
        }
        if let suitcaseID = context.request.source.suitcaseID {
            do { try await services.suitcases.markUsed(suitcaseID, at: context.now) } catch { kept = false }
        }
        update(id) { $0.isKept = kept }
    }

    /// 33a: keeps the finished picture in her Pictures, then lets go of the files only the phone
    /// needed to make it (her photo with her real head, her outline and the head shape). What was
    /// sent stays with the picture for "See what was sent".
    private func keepPicture(_ id: AIJob.ID, services: NookServices) async {
        guard let picture = job(id)?.picture else { return }
        do {
            try await services.pictures.save(picture)
        } catch {
            update(id) { $0.isKept = false }
            return
        }
        update(id) { $0.isKept = true }
        letGoOfUpload(id, keepingSent: true)
    }

    /// 33a: removes a try-on job's work files (and, unless a picture keeps them, the sent ones),
    /// and forgets them in the job, so the sweep doesn't keep them either.
    private func letGoOfUpload(_ id: AIJob.ID, keepingSent: Bool) {
        guard let services, let pipeline = services.tryOnPipeline, let job = job(id),
            case .tryOn(var request) = job.request
        else { return }
        let upload = request.upload
        guard upload.work != nil || !keepingSent else { return }
        request.upload.work = nil
        update(id) { $0.request = .tryOn(request) }
        Task { await pipeline.discard(upload, keepingSent: keepingSent) }
    }

    /// The banner in the app, or a notification in the background. Nothing for a result she's
    /// looking at.
    private func announce(_ id: AIJob.ID) {
        guard let job = job(id) else { return }
        // In the background she isn't looking at any screen, even the one left open on the
        // result: a notification says it's done, and the screen marks it seen when she's back.
        if !isInForeground {
            if job.state == .done {
                let kind = job.kind
                Task { await notifier.notifyDone(kind, id: id) }
            }
            if onScreen[id] == nil { announcement = id }
            return
        }
        if onScreen[id] != nil {
            if job.state == .done { markSeen(id) }
        } else {
            announcement = id
        }
    }

    private func finish(
        _ id: AIJob.ID, _ state: AIJob.State, result: AIJob.Result? = nil, failure: AIJob.Failure? = nil
    ) {
        update(id) {
            $0.state = state
            $0.result = result ?? $0.result
            $0.failure = failure
            $0.finishedAt = now()
        }
        finishWaiters(id)
    }

    private func update(_ id: AIJob.ID, _ change: (inout AIJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
        jobs[index].updatedAt = now()
        persist(jobs[index])
    }

    /// Saves in order, so a later state never lands before an earlier one.
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    private func persist(_ job: AIJob) {
        let previous = lastSave
        let store = store
        lastSave = Task {
            await previous?.value
            try? await store.save(job)
        }
    }

    /// Waits for every save so far, for tests and before the app is suspended.
    public func saved() async {
        await lastSave?.value
    }

    private func finishWaiters(_ id: AIJob.ID) {
        let job = job(id)
        for waiter in waiters.removeValue(forKey: id) ?? [] { waiter.resume(returning: job) }
        if activeJobs.isEmpty { finishIdleWaiters() }
    }

    private func finishIdleWaiters() {
        let waiting = idleWaiters
        idleWaiters = []
        for waiter in waiting { waiter.resume() }
    }
}

/// Delete my data's handle on the jobs: stops every one and forgets them all.
public struct AIJobsEraser: ErasableStore {
    private let jobs: AIJobs

    public init(_ jobs: AIJobs) {
        self.jobs = jobs
    }

    public func eraseAll() async throws(StoreError) {
        try await jobs.eraseAll()
    }
}
