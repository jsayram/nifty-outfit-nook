import Models
import Observation
import Synchronization

/// Runs one cloud call for a screen (Phase 26, PRD 11.7): at most one at a time, cancelled when
/// she leaves the screen or taps Cancel, a plain "taking longer than usual" note after ten
/// seconds, and a failure in plain words that VoiceOver reads aloud. Nothing is left running when
/// the screen's model goes away.
///
/// Leaving a screen cancels the request, not the charge: a paid request that had already reached
/// the server is kept there under its Idempotency-Key, and asking again with that key (a
/// `PaidActionAttempt`) gets the answer back without running or counting it twice.
@Observable
public final class CloudTask {
    public enum State: Equatable {
        case idle
        case running
        /// Running for longer than `slowAfter`: time to say so and offer Cancel (PRD 11.7).
        case takingLong
        /// Finished without an answer. `message` has the words.
        case failed(message: String)
        case finished
    }

    public private(set) var state = State.idle

    public var isRunning: Bool { state == .running || state == .takingLong }
    /// The failure to show, if the last call failed. Nil after a cancellation.
    public var message: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    @ObservationIgnored private let slowAfter: Duration
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let holder = Holder()
    @ObservationIgnored private var generation = 0

    /// - Parameters:
    ///   - slowAfter: when to flip to `takingLong`. PRD 11.7 wants a useful status by ten seconds.
    ///   - announce: how a failure or a slow call is spoken. VoiceOver by default.
    public init(
        slowAfter: Duration = .seconds(10),
        announce: @escaping @MainActor (String) -> Void = { CloudProblemText.announce($0) }
    ) {
        self.slowAfter = slowAfter
        self.announce = announce
    }

    /// Starts `work`, unless one is already running. `work` keeps its own answer; this keeps only
    /// how it ended. A cancelled `work` (it throws `.account(.cancelled)`) ends quietly.
    public func start(_ work: @escaping @MainActor () async throws(CloudLimitProblem) -> Void) {
        guard !isRunning else { return }
        generation += 1
        let mine = generation
        state = .running
        let slowAfter = slowAfter
        let task = Task { @MainActor [weak self] in
            let timer = Task { @MainActor [weak self] in
                guard (try? await Task.sleep(for: slowAfter)) != nil, let self, self.generation == mine,
                    self.state == .running
                else { return }
                self.state = .takingLong
                self.announce(Self.takingLongText)
            }
            defer { timer.cancel() }
            do throws(CloudLimitProblem) {
                try await work()
                self?.end(mine, .finished)
            } catch {
                if Task.isCancelled || error == .account(.cancelled) {
                    self?.end(mine, .idle)
                } else {
                    let text = CloudLimitText.message(for: error)
                    self?.end(mine, .failed(message: text))
                    self?.announce(text)
                }
            }
        }
        holder.set(task)
    }

    /// Stops the call, quietly. Safe to call at any time, as a screen does when she leaves it.
    public func cancel() {
        generation += 1
        holder.cancel()
        if isRunning { state = .idle }
    }

    /// Clears a shown failure, for the next try.
    public func dismissFailure() {
        if case .failed = state { state = .idle }
    }

    private func end(_ mine: Int, _ final: State) {
        guard generation == mine else { return }
        state = final
    }

    static var takingLongText: String {
        String(
            localized: "This is taking longer than usual. You can wait or cancel.", bundle: .module,
            comment: "Cloud action still running after ten seconds, said aloud and shown")
    }

    /// Holds the running task, and cancels it if the `CloudTask` is released first.
    private final class Holder: Sendable {
        private let task = Mutex<Task<Void, Never>?>(nil)
        func set(_ new: Task<Void, Never>) { task.withLock { $0 = new } }
        func cancel() { task.withLock { $0?.cancel() } }
        deinit { task.withLock { $0?.cancel() } }
    }
}
