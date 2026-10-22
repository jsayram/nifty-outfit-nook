import Foundation
import Models
import Testing

@testable import Networking

/// Phase 27c against the fake backend: a styling job the app was killed in the middle of is asked
/// again after the relaunch with the same Idempotency-Key, and the server answers from its record.
/// One action, one job run, one use of her allowance.
@MainActor
@Suite("Background AI jobs")
struct AIJobsResumeTests {
    let base = CloudStylistTests()

    @Test func aJobResumedAfterARelaunchIsNotRunOrChargedTwice() async throws {
        let paid = try await base.paid()
        var services = NookServices.unavailable
        services.stylist = base.stylist(paid)
        let store = InMemoryAIJobStore()

        let first = AIJobs(store: store)
        let job = try first.startStyling(CloudStylistTests.context(), services: services)
        #expect(await first.finished(job.id)?.state == .done)
        await first.saved()
        #expect(base.backend.paidJobsRun == 1)

        // The app was killed before it saw the answer: the kept job still says it's running.
        var killed = try #require(try await store.jobs().first)
        killed.state = .running
        killed.result = nil
        killed.finishedAt = nil
        try await store.save(killed)

        let relaunched = AIJobs(store: store, makeKey: { "idem_never_used_000" })
        await relaunched.resume(with: services)
        let resumed = try #require(await relaunched.finished(job.id))
        #expect(resumed.state == .done)
        #expect(resumed.outcome?.result?.versions.count == 3)
        #expect(base.backend.paidJobsRun == 1)
        #expect(base.backend.paidActionCount == 1)
        let usage = try await paid.usage()
        #expect(usage.allowance(.styleFull)?.usedToday == 1)
    }
}
