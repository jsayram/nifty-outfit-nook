import Foundation

/// Timing for the speed checks on the large closet.
///
/// Swift Testing runs suites in parallel, and a shared CI runner is slower than a dev Mac, so a
/// single timing can catch a stall that has nothing to do with the code under test. Each check
/// takes the fastest of a few runs, and on CI allows three times the local bound. A failure still
/// means the work itself got many times slower. FixturesTests has a copy of this file.
enum SpeedCheck {
    /// `scripts/test.sh` sets `TEST_RUNNER_NOOK_CI` when `CI` is set, and xcodebuild passes it to
    /// the tests as `NOOK_CI`.
    static let isOnCI = ProcessInfo.processInfo.environment["NOOK_CI"] != nil

    /// The bound for a check: `local` on a dev Mac, three times that on CI.
    static func limit(_ local: Duration) -> Duration {
        isOnCI ? local * 3 : local
    }

    /// The fastest of `runs` timings of `work`.
    static func fastest(of runs: Int = 3, _ work: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        var fastest = Duration.seconds(Int64.max)
        for _ in 0..<runs {
            let start = clock.now
            try work()
            fastest = min(fastest, clock.now - start)
        }
        return fastest
    }

    /// The fastest of `runs` timings of async `work`.
    static func fastest(
        of runs: Int = 3, isolation: isolated (any Actor)? = #isolation, _ work: () async throws -> Void
    ) async rethrows -> Duration {
        let clock = ContinuousClock()
        var fastest = Duration.seconds(Int64.max)
        for _ in 0..<runs {
            let start = clock.now
            try await work()
            fastest = min(fastest, clock.now - start)
        }
        return fastest
    }
}
