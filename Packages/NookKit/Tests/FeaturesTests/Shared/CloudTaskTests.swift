import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Features

/// Phase 26: what a screen sees while a cloud call runs, fails, is cancelled by leaving, or takes
/// longer than ten seconds (shortened here), and what VoiceOver is told.
@MainActor
struct CloudTaskTests {
    final class Spoken {
        var lines: [String] = []
    }

    /// Work that waits until it is cancelled, and says so.
    final class Waiter: Sendable {
        private let cancelled = Mutex(false)
        private let started = Mutex(false)
        var wasCancelled: Bool { cancelled.withLock { $0 } }
        var hasStarted: Bool { started.withLock { $0 } }

        func wait(for duration: Duration = .seconds(30)) async throws(CloudLimitProblem) {
            started.withLock { $0 = true }
            do {
                try await Task.sleep(for: duration)
            } catch {
                cancelled.withLock { $0 = true }
                throw .account(.cancelled)
            }
        }
    }

    /// Work that goes on after it is cancelled, until the test lets it finish.
    final class Gate: Sendable {
        private enum State {
            case closed
            case waiting(UnsafeContinuation<Void, Never>)
            case open
        }
        private let state = Mutex(State.closed)

        func wait() async {
            await withUnsafeContinuation { continuation in
                let open = state.withLock { state -> Bool in
                    if case .open = state { return true }
                    state = .waiting(continuation)
                    return false
                }
                if open { continuation.resume() }
            }
        }

        func open() {
            let waiting = state.withLock { state -> UnsafeContinuation<Void, Never>? in
                defer { state = .open }
                if case .waiting(let continuation) = state { return continuation }
                return nil
            }
            waiting?.resume()
        }
    }

    /// The task's clock is one the test moves, so "ten seconds" pass when the test says so.
    let clock = ManualClock()

    func task(slowAfter: Duration = .seconds(10), _ spoken: Spoken) -> CloudTask {
        CloudTask(slowAfter: slowAfter, clock: clock, announce: { spoken.lines.append($0) })
    }

    func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        // Up to 30 seconds: the whole test run shares the main actor on a busy runner.
        for _ in 0..<3000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func aCallThatWorksEndsFinishedAndSaysNothing() async {
        let spoken = Spoken()
        let cloud = task(spoken)
        #expect(cloud.state == .idle)
        cloud.start { () async throws(CloudLimitProblem) in }
        #expect(cloud.isRunning)
        #expect(await eventually { cloud.state == .finished })
        #expect(cloud.message == nil)
        #expect(spoken.lines.isEmpty)
    }

    @Test func aFailureIsShownInPlainWordsAndSpoken() async {
        let spoken = Spoken()
        let cloud = task(spoken)
        cloud.start { () async throws(CloudLimitProblem) in throw .account(.offline) }
        #expect(await eventually { cloud.message != nil })
        #expect(cloud.message == "You're offline. Your closet still works on this iPhone.")
        #expect(spoken.lines == ["You're offline. Your closet still works on this iPhone."])
        cloud.dismissFailure()
        #expect(cloud.state == .idle)
    }

    @Test func eachKindOfFailureHasItsOwnWords() async {
        let spoken = Spoken()
        let cloud = task(spoken)
        let problems: [CloudLimitProblem] = [
            .account(.timedOut), .account(.serverError), .account(.unavailable(retryAfterSeconds: 90)),
            .rateLimited(retryAfterSeconds: 12), .busy(retryAfterSeconds: 2), .didNotFinish(retryAfterSeconds: nil),
        ]
        for problem in problems {
            cloud.start { () async throws(CloudLimitProblem) in throw problem }
            #expect(await eventually { cloud.message != nil })
            cloud.dismissFailure()
        }
        #expect(spoken.lines.count == problems.count)
        #expect(Set(spoken.lines).count == problems.count)
        #expect(spoken.lines.allSatisfy { !$0.isEmpty })
    }

    @Test func cancellingEndsQuietlyAndStopsTheWork() async {
        let spoken = Spoken()
        let cloud = task(spoken)
        let waiter = Waiter()
        cloud.start { () async throws(CloudLimitProblem) in try await waiter.wait() }
        #expect(await eventually { waiter.hasStarted })
        cloud.cancel()
        #expect(cloud.state == .idle)
        #expect(await eventually { waiter.wasCancelled })
        #expect(cloud.message == nil)
        #expect(spoken.lines.isEmpty)
    }

    @Test func leavingTheScreenCancelsTheCall() async {
        let spoken = Spoken()
        let waiter = Waiter()
        var cloud: CloudTask? = task(spoken)
        cloud?.start { () async throws(CloudLimitProblem) in try await waiter.wait() }
        #expect(await eventually { waiter.hasStarted })
        // The screen and its model go away: nothing is left running.
        cloud = nil
        #expect(await eventually { waiter.wasCancelled })
        #expect(spoken.lines.isEmpty)
    }

    @Test func aSlowCallSaysSoOnceAndKeepsRunning() async {
        let spoken = Spoken()
        let cloud = task(spoken)
        let waiter = Waiter()
        // The work only ends when it is cancelled, so how long the runner takes to notice is
        // never a race against the work finishing.
        cloud.start { () async throws(CloudLimitProblem) in try await waiter.wait() }
        // Nine seconds in: still just running. Then the tenth.
        await clock.waitForSleepers(1)
        clock.advance(by: .seconds(9))
        #expect(cloud.state == .running)
        clock.advance(by: .seconds(1))
        #expect(await eventually { cloud.state == .takingLong })
        #expect(cloud.isRunning)
        #expect(spoken.lines == ["This is taking longer than usual. You can wait or cancel."])
        clock.advance(by: .seconds(600))
        await Task.yield()
        #expect(spoken.lines.count == 1)
        cloud.cancel()
        #expect(cloud.state == .idle)
    }

    @Test func aCallThatEndsInTimeNeverSaysItIsSlow() async {
        let spoken = Spoken()
        let cloud = task(spoken)
        cloud.start { () async throws(CloudLimitProblem) in }
        #expect(await eventually { cloud.state == .finished })
        // Long after it ended, there is no timer left to go off.
        clock.advance(by: .seconds(600))
        await Task.yield()
        #expect(cloud.state == .finished)
        #expect(spoken.lines.isEmpty)
    }

    @Test func onlyOneCallRunsAtATime() async {
        let spoken = Spoken()
        let cloud = task(spoken)
        let waiter = Waiter()
        let second = Mutex(false)
        cloud.start { () async throws(CloudLimitProblem) in try await waiter.wait() }
        cloud.start { () async throws(CloudLimitProblem) in second.withLock { $0 = true } }
        // The first call ends when it is cancelled, and the second never began.
        #expect(await eventually { waiter.hasStarted })
        cloud.cancel()
        #expect(await eventually { waiter.wasCancelled })
        #expect(second.withLock { $0 } == false)
    }

    @Test func aCancelledCallsLateAnswerDoesNotChangeTheNextCall() async {
        let spoken = Spoken()
        let cloud = task(spoken)
        let gate = Gate()
        let answered = Mutex(false)
        // The first call ignores cancellation and fails late; it must not overwrite the second's state.
        cloud.start { () async throws(CloudLimitProblem) in
            await gate.wait()
            answered.withLock { $0 = true }
            throw .account(.serverError)
        }
        cloud.cancel()
        let waiter = Waiter()
        cloud.start { () async throws(CloudLimitProblem) in try await waiter.wait() }
        #expect(await eventually { waiter.hasStarted })
        // The late answer arrives while the second call is running.
        gate.open()
        #expect(await eventually { answered.withLock { $0 } })
        for _ in 0..<10 { await Task.yield() }
        #expect(cloud.state == .running)
        #expect(spoken.lines.isEmpty)
        cloud.cancel()
    }
}

@MainActor
struct ConnectionStatusTests {
    struct ManualSource: ConnectivitySource {
        let stream: AsyncStream<ConnectionState>
        func states() -> AsyncStream<ConnectionState> { stream }
    }

    @Test func itFollowsTheSourceAndOnlyOfflineCounts() async {
        let (stream, continuation) = AsyncStream<ConnectionState>.makeStream()
        let status = ConnectionStatus()
        #expect(status.state == .unknown)
        #expect(!status.isOffline)
        let follower = Task { await status.follow(ManualSource(stream: stream)) }
        continuation.yield(.offline)
        for _ in 0..<3000 where !status.isOffline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(status.isOffline)
        continuation.yield(.online)
        for _ in 0..<3000 where status.isOffline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(status.state == .online)
        follower.cancel()
        continuation.finish()
        await follower.value
    }

    @Test func aFixedSourceReportsOnce() async {
        let status = ConnectionStatus()
        await status.follow(FixedConnectivitySource(.offline))
        #expect(status.isOffline)
    }
}

struct CloudProblemTextTests {
    @Test func everyProblemButACancellationHasPlainWords() {
        let problems: [AccountProblem] = [
            .offline, .timedOut, .rateLimited(retryAfterSeconds: 30), .forbidden, .unavailable(retryAfterSeconds: 60),
            .unavailable(retryAfterSeconds: nil), .signedOut, .serverError, .updateRequired, .invalidResponse,
            .rejected,
        ]
        for problem in problems {
            let text = CloudProblemText.message(for: problem)
            #expect(text?.isEmpty == false, "\(problem)")
            #expect(text?.hasSuffix(".") == true, "\(problem)")
        }
        #expect(CloudProblemText.message(for: .cancelled) == nil)
    }

    @Test func theWordsAreTheSameWhereAPaidActionMeetsThem() {
        for problem: AccountProblem in [.timedOut, .serverError, .unavailable(retryAfterSeconds: 90), .offline] {
            #expect(CloudLimitText.message(for: .account(problem)) == CloudProblemText.message(for: problem))
        }
    }

    @Test func aWaitIsSaidInSecondsOrMinutes() {
        #expect(
            CloudProblemText.message(for: .unavailable(retryAfterSeconds: 90))
                == "This isn't available right now. Try again in 2 minutes.")
        #expect(
            CloudProblemText.message(for: .rateLimited(retryAfterSeconds: 12))
                == "You've asked a lot in the last minute. Try again in 12 seconds.")
        #expect(
            CloudProblemText.message(for: .timedOut) == "That's taking longer than it should. Try again in a moment.")
    }
}
