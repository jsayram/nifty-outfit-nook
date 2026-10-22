import Foundation
import Models
import NookTestSupport
import Testing

/// 33c: where a try-on picture is, as the loading screen's captions show it. Built from the
/// phone's own steps and from the job's state, never from a timer.
struct TryOnProgressTests {
    private func job(_ state: AIJob.State, stage: TryOnStage? = nil) -> AIJob {
        let upload = TryOnUpload(
            sent: TryOnSent(person: .stored("p"), garments: []), work: nil,
            geometry: TryOnGeometry(width: 4, height: 4, face: [1, 1, 1, 1]), contextRevision: "rev")
        var job = AIJob(
            kind: .tryOn, idempotencyKey: "idem_progress_000000",
            request: .tryOn(
                TryOnJobRequest(look: Make.look("o-1", garments: ["g-1"]), upload: upload, consentVersion: "tryon-1")),
            createdAt: TestTime.now)
        job.state = state
        job.tryOnStage = stage
        return job
    }

    private func marks(_ progress: TryOnProgress) -> [TryOnProgress.Mark] {
        TryOnStage.allCases.map { progress.mark(for: $0) }
    }

    @Test func theStepsAreInTheOrderTheAppDoesThem() {
        #expect(
            TryOnStage.allCases == [.hidingFace, .studioBackdrop, .checkingFace, .dressing, .restoring])
        // Only the dressing leaves the phone, and three steps come before anything is sent.
        #expect(TryOnStage.allCases.filter { !$0.isOnThePhone } == [.dressing])
        #expect(TryOnStage.allCases.filter(\.isBeforeSending) == [.hidingFace, .studioBackdrop, .checkingFace])
    }

    @Test func eachPhoneStepMarksTheEarlierOnesDone() {
        let progress = TryOnProgress.preparing(.studioBackdrop)
        #expect(marks(progress) == [.done, .doing, .todo, .todo, .todo])
        #expect(progress.nothingSentYet)
    }

    @Test func aRefusalOnThePhoneStopsAtThatStepAndNothingWasSent() {
        let progress = TryOnProgress.stopped(at: .checkingFace)
        #expect(marks(progress) == [.done, .done, .stopped, .todo, .todo])
        #expect(progress.nothingSentYet)
    }

    @Test func aJobMapsFromItsState() throws {
        // Waiting for an earlier job: all three phone steps are done, nothing is sent.
        let queued = try #require(TryOnProgress(job: job(.queued)))
        #expect(marks(queued) == [.done, .done, .done, .waiting, .todo])
        #expect(queued.isWaiting && queued.nothingSentYet)

        // Running before its first step is recorded still means the request is out.
        let running = try #require(TryOnProgress(job: job(.running)))
        #expect(marks(running) == [.done, .done, .done, .doing, .todo])
        #expect(!running.nothingSentYet)

        // Taking longer: still the dressing, now said as such.
        let slow = try #require(TryOnProgress(job: job(.stillRunning, stage: .dressing)))
        #expect(slow.isStillGoing && slow.stage == .dressing)

        // The picture is back: her head goes back on.
        let restoring = try #require(TryOnProgress(job: job(.running, stage: .restoring)))
        #expect(marks(restoring) == [.done, .done, .done, .done, .doing])
        #expect(!restoring.nothingSentYet)

        let done = try #require(TryOnProgress(job: job(.done, stage: .restoring)))
        #expect(marks(done) == [.done, .done, .done, .done, .done])
    }

    @Test func aFailedJobStopsAtTheStepItWasOn() throws {
        let dressing = try #require(TryOnProgress(job: job(.failed, stage: .dressing)))
        #expect(marks(dressing) == [.done, .done, .done, .stopped, .todo])
        let restoring = try #require(TryOnProgress(job: job(.failed, stage: .restoring)))
        #expect(marks(restoring) == [.done, .done, .done, .done, .stopped])
        // A job that failed before it recorded a step failed at the request.
        let early = try #require(TryOnProgress(job: job(.failed)))
        #expect(early.stage == .dressing && early.isStopped)
    }

    @Test func onlyATryOnJobHasProgress() {
        var styling = job(.running)
        styling = AIJob(
            kind: .styling, idempotencyKey: "idem_styling_00000", request: styling.request, createdAt: TestTime.now)
        #expect(TryOnProgress(job: styling) == nil)
    }

    @Test func theStageSurvivesBeingKept() throws {
        // A job is kept as JSON, and one kept before 33c has no stage.
        let kept = job(.running, stage: .restoring)
        let decoded = try JSONDecoder().decode(AIJob.self, from: JSONEncoder().encode(kept))
        #expect(decoded.tryOnStage == .restoring)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(kept)) as? [String: Any])
        object["tryOnStage"] = nil
        let older = try JSONDecoder().decode(AIJob.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.tryOnStage == nil && older.state == .running)
    }

    @Test func theConsentStoreRemembersTheWalkthroughApartFromTheConsent() async throws {
        let store = InMemoryTryOnConsentStore(TryOnConsent(agreedAt: TestTime.now))
        #expect(!store.hasSeenWalkthrough())
        store.markWalkthroughSeen()
        store.save(nil)
        // Turning the switch off keeps that she has watched it; Delete my data erases both.
        #expect(store.hasSeenWalkthrough() && store.current() == nil)
        try await store.eraseAll()
        #expect(!store.hasSeenWalkthrough())
    }
}
