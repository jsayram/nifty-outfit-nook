import Synchronization

/// A clock that only moves when a test says so, so a timeout or a "taking longer than usual" note
/// happens because the test advanced the clock, not because a busy machine was slow.
///
/// Sleeping on it suspends until `advance(by:)` reaches the wake-up time, or until the sleeping
/// task is cancelled. Two ways to follow along without polling:
///
/// - `waitForSleepers(_:)` returns once that many tasks are asleep on the clock, so a test knows a
///   timer has really started before it advances the clock past it.
/// - `skip(_:)` is a sleep that returns at once and moves the clock forward by that much, for the
///   waits between retries that a test only wants to record.
public final class ManualClock: Clock, Sendable {
    public struct Instant: InstantProtocol {
        public var offset: Duration

        public init(offset: Duration) {
            self.offset = offset
        }

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: Int
        let wake: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct Watcher {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextID = 0
        var sleepers: [Sleeper] = []
        var watchers: [Watcher] = []
    }

    private let state = Mutex(State())

    public init() {}

    public var now: Instant { state.withLock { $0.now } }
    public var minimumResolution: Duration { .zero }

    /// How many tasks are asleep on the clock right now.
    public var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Next {
                    case resume, cancel
                    case sleep([CheckedContinuation<Void, Never>])
                }
                let next = state.withLock { state -> Next in
                    if Task.isCancelled { return .cancel }
                    if deadline <= state.now { return .resume }
                    state.sleepers.append(Sleeper(id: id, wake: deadline, continuation: continuation))
                    let ready = state.watchers.filter { $0.count <= state.sleepers.count }
                    state.watchers.removeAll { $0.count <= state.sleepers.count }
                    return .sleep(ready.map(\.continuation))
                }
                switch next {
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                case .sleep(let watchers): for watcher in watchers { watcher.resume() }
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the clock forward, and wakes every sleeper whose time has come, earliest first.
    public func advance(by duration: Duration) {
        let woken = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.wake <= state.now }.sorted { $0.wake < $1.wake }
            state.sleepers.removeAll { $0.wake <= state.now }
            return due
        }
        for sleeper in woken { sleeper.continuation.resume() }
    }

    /// Waits until at least `count` tasks are asleep on the clock.
    public func waitForSleepers(_ count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { state -> Bool in
                if state.sleepers.count >= count { return true }
                state.watchers.append(Watcher(count: count, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    /// Waits for a task to fall asleep on the clock, then moves the clock to the moment the
    /// earliest sleeper wakes at. The way a test fires the timer that is running right now.
    public func advanceToNextSleeper() async {
        await waitForSleepers(1)
        let wait = state.withLock { state in
            state.sleepers.map(\.wake).min().map { state.now.duration(to: $0) }
        }
        if let wait { advance(by: wait) }
    }

    /// A sleep that doesn't wait: it moves the clock forward by `duration` and returns. Stops with
    /// a cancellation if the task was cancelled, like a real sleep.
    public func skip(_ duration: Duration) async throws {
        try Task.checkCancellation()
        advance(by: duration)
    }
}
