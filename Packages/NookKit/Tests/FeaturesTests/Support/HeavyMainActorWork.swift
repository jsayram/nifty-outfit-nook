import Testing

/// Runs the tests that do long stretches of work on the main actor one at a time, while every
/// other test still runs in parallel.
///
/// Why (Phase 18): Swift Testing starts every test in the target at once, and the main actor
/// takes its jobs in the order they arrive. A snapshot test draws its page and compares it on
/// the main actor in one go, and the large-closet speed checks sort and filter thousands of
/// pieces there. With some 300 of those in flight, a test that needs the main actor several
/// times waited behind all of them for each turn, so almost every test in the target finished
/// only as the target drained (locally a median of 15 of 20 seconds; on CI about 200 seconds).
/// `waitUntil` in the Your looks tests needs a few turns, so it ran out at 20 seconds in Phase
/// 12b and at 60 in Phase 17, and the bound went up to 600.
///
/// With this trait at most one of these tests has work on the main actor at a time. The rest
/// wait for their turn off the main actor, so the queue stays short and other tests get their
/// turns in well under a second. The target takes about as long as before, because the main
/// actor did this work one piece at a time anyway.
///
/// Put it on a suite that draws snapshots, `@Suite(.heavyMainActorWork)`, or on one test that
/// runs long on the main actor, `@Test(.heavyMainActorWork)`.
struct HeavyMainActorWork: SuiteTrait, TestTrait, TestScoping {
    /// Every test in a suite takes its own turn.
    var isRecursive: Bool { true }

    /// One turn per test case, so the cases of a parameterized test take turns too.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        await MainActorTurn.shared.take()
        do {
            try await function()
        } catch {
            await MainActorTurn.shared.give()
            throw error
        }
        await MainActorTurn.shared.give()
    }
}

extension Trait where Self == HeavyMainActorWork {
    /// See `HeavyMainActorWork`.
    static var heavyMainActorWork: Self { HeavyMainActorWork() }
}

/// The one turn these tests share, handed on in the order they asked for it.
private actor MainActorTurn {
    static let shared = MainActorTurn()

    private var taken = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func take() async {
        guard taken else {
            taken = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the turn straight to the next test waiting, if there is one.
    func give() {
        if waiting.isEmpty {
            taken = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
