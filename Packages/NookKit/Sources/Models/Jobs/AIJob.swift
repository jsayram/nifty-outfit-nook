import Foundation
import Synchronization

// Background AI jobs (Phase 27c; Jose, 21 October 2026: "any AI calls or AI stylist conversations
// persist if she navigates away"). Every paid AI action is one job: Style Me's outfit ideas now,
// Ask stylist's answers once its screen exists, and try-on pictures in 33a. A job keeps its own
// Idempotency-Key from the first try to the last, across a relaunch, so the server answers a
// repeat from its record and never runs or charges it twice (24b). See docs/background-ai-jobs.md.

/// One paid AI action, from her tap until it's done, failed or she cancels it.
///
/// Data tier: **Personal** (it carries the styling request, or her question, and the result). Kept
/// in the store on the iPhone only, never in a backup (it's this iPhone's work in progress, tied to
/// this iPhone's sign-in), and erased by Delete my data.
public struct AIJob: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<AIJob>

    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        /// Style Me's outfit ideas.
        case styling
        /// An Ask stylist answer in a conversation.
        case askStylist
        /// A try-on picture (33a plugs in here).
        case tryOn
    }

    public enum State: String, Hashable, Sendable, Codable {
        /// Waiting for the job before it: the server runs one paid action at a time per account.
        case queued
        /// Sent, waiting for the answer.
        case running
        /// The answer didn't come back in time (Phase 26's deadline, or "still running"), so the
        /// job asks again with the same key every so often until the server says it's done.
        case stillRunning
        case done
        case failed
        /// Only her Cancel does this. Leaving a screen never does.
        case cancelled

        /// Whether the job can still change on its own.
        public var isActive: Bool { self == .queued || self == .running || self == .stillRunning }
    }

    /// Why a job didn't finish, in the words the screens already use.
    public enum Failure: Hashable, Sendable, Codable {
        case offline
        case notCompleted
        case needsConsent
        case requestChanged
        case limited(CloudLimitProblem)
    }

    /// What the job asks for, kept so a resumed job sends exactly the same body with the same key.
    public enum Request: Hashable, Sendable, Codable {
        case styling(StylingContext, consentVersion: String)
        case ask(AskStylistRequest)
        /// 33a: a try-on picture, prepared on the phone (only the faceless photo and the garment
        /// photos are sent).
        case tryOn(TryOnJobRequest)
    }

    /// Where the result is. Style Me's looks are also in her history (the look store); the outcome
    /// is kept here too so the screen shows exactly what the stylist answered, with its notes.
    public enum Result: Hashable, Sendable, Codable {
        case styling(StyleOutcome)
        /// The stylist's turn in a conversation.
        case answer(thread: StylistThread.ID, turn: StylistThread.Turn.ID)
        /// 33a: the finished try-on picture, with her own head back on it.
        case tryOn(TryOnPicture)
    }

    public let id: ID
    public let kind: Kind
    /// Sent with every try of this job, and again after a relaunch.
    public let idempotencyKey: String
    public var request: Request
    public var state: State
    public var createdAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?
    public var result: Result?
    public var failure: Failure?
    /// Phase 35: the server's ID for this job's action, once it has said it is running. A job
    /// resumed after a relaunch, or asked again after a late answer, asks for this action's
    /// status with it, instead of sending the photos again. Missing in jobs kept before this.
    public var actionID: String?
    /// True once the request may have reached the server. A resumed job that was never sent is
    /// treated as new; one that was is asked again with its key.
    public var wasSent: Bool
    /// She has seen the result (opened it, or was already on it), so no banner or dot.
    public var isSeen: Bool
    /// The result is also in her history. False when the store couldn't be written (the iPhone
    /// was locked), so the next foreground writes it.
    public var isKept: Bool
    /// 33c: a try-on job's step while it runs (and the step it stopped at), so the loading screen
    /// shows real progress. `nil` for other jobs and until the first step starts.
    public var tryOnStage: TryOnStage?

    public init(
        id: ID = .random(), kind: Kind, idempotencyKey: String, request: Request, state: State = .queued,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.idempotencyKey = idempotencyKey
        self.request = request
        self.state = state
        self.createdAt = createdAt
        updatedAt = createdAt
        finishedAt = nil
        result = nil
        failure = nil
        wasSent = false
        actionID = nil
        isSeen = false
        isKept = true
        tryOnStage = nil
    }

    /// The Style Me request this job styles, if it's a styling job.
    public var styleRequestID: StyleRequest.ID? {
        if case .styling(let context, _) = request { context.request.id } else { nil }
    }

    /// 33a: the try-on picture, when it's done.
    public var picture: TryOnPicture? {
        if case .tryOn(let picture) = result { picture } else { nil }
    }

    /// 33a: the look a try-on job pictures.
    public var tryOnLookID: Look.ID? {
        if case .tryOn(let request) = request { request.look.id } else { nil }
    }

    /// The styling outcome, when it's done.
    public var outcome: StyleOutcome? {
        if case .styling(let outcome) = result { outcome } else { nil }
    }
}

/// Ask stylist's question as a job keeps it: everything `StyleCall.question` is built from, so a
/// resumed job builds the same body.
public struct AskStylistRequest: Hashable, Sendable, Codable {
    public var thread: StylistThread.ID
    /// Her turn in the thread that this job answers.
    public var turn: StylistThread.Turn.ID
    public var text: String
    public var look: Look
    public var pieces: [Garment]
    public var earlier: [StylistThread.Turn]
    public var consentVersion: String
    /// D10: her measurements and weight when the job was made, sent only under a consent that
    /// names them. **Sensitive**.
    public var measurements: StyleCall.Measurements?

    public init(
        thread: StylistThread.ID, turn: StylistThread.Turn.ID, text: String, look: Look, pieces: [Garment],
        earlier: [StylistThread.Turn], consentVersion: String, measurements: StyleCall.Measurements? = nil
    ) {
        self.thread = thread
        self.turn = turn
        self.text = text
        self.look = look
        self.pieces = pieces
        self.earlier = earlier
        self.consentVersion = consentVersion
        self.measurements = measurements
    }

    /// The contract's request, built the same way every time.
    public var call: StyleCall {
        StyleCall.question(
            text, about: look, pieces: pieces,
            earlier: earlier.map { StyleCall.Turn(from: $0.from == .her ? .her : .stylist, text: $0.text) },
            consentVersion: consentVersion, measurements: measurements)
    }
}

/// Where jobs are kept. Erased by Delete my data.
public protocol AIJobStore: ErasableStore {
    func jobs() async throws(StoreError) -> [AIJob]
    func save(_ job: AIJob) async throws(StoreError)
    func remove(_ ids: [AIJob.ID]) async throws(StoreError)
}

/// Jobs in memory: previews, tests and the debug sample closet.
public final class InMemoryAIJobStore: AIJobStore {
    private let state: Mutex<[AIJob.ID: AIJob]>

    public init(_ jobs: [AIJob] = []) {
        state = Mutex(Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }))
    }

    public func jobs() async throws(StoreError) -> [AIJob] {
        state.withLock { Array($0.values) }.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ job: AIJob) async throws(StoreError) { state.withLock { $0[job.id] = job } }

    public func remove(_ ids: [AIJob.ID]) async throws(StoreError) {
        state.withLock { jobs in for id in ids { jobs[id] = nil } }
    }

    public func eraseAll() async throws(StoreError) { state.withLock { $0 = [:] } }
}
