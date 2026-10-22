import Fixtures
import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Features

/// Send feedback to the support queue (Phase 24d): the route, what's shown is what's sent, a note
/// that can't go stays as she wrote it and goes when she taps Send again, a screenshot she chose,
/// and her closet's size only when she ticks it.
@MainActor
struct FeedbackQueueTests {
    private let details = FeedbackDiagnostics(
        appVersion: "0.1", build: "14", systemVersion: "26.5", deviceModel: "iPhone13,2")
    private let counts = FeedbackClosetCounts(pieces: 42, looks: 9, suitcases: 2)

    private func model(
        service: ScriptedFeedbackService = ScriptedFeedbackService(), store: (any FeedbackDraftStore)? = nil,
        screenshots: any FeedbackScreenshotPreparing = ScriptedScreenshots(),
        spoken: SpokenLines = SpokenLines(), health: (@Sendable () async -> DeviceHealthSummary?)? = nil
    ) async -> FeedbackModel {
        let counts = counts
        let model = FeedbackModel(
            diagnostics: details, store: store, service: service, screenshots: screenshots,
            closetCounts: { counts }, deviceHealth: health, announce: { spoken.add($0) })
        await model.checkRoute()
        return model
    }

    // MARK: The route

    @Test func theShareSheetIsTheWayUntilSheCanSendToTheQueue() async {
        let signedOut = ScriptedFeedbackService(canSend: false)
        let model = await model(service: signedOut)
        #expect(model.route == .shareSheet)
        // Extras she can't send aren't part of a note that goes to the share sheet.
        model.message = "Hello"
        model.replyAddress = "lily@example.com"
        model.includesClosetCounts = true
        await model.finishCounting()
        await model.attachScreenshot(Data([1]))
        let text = model.preview
        #expect(
            text == """
                Nifty Outfit Nook feedback
                About: Something’s wrong

                Hello
                """)
        #expect(await signedOut.submissions().isEmpty)

        // Signed in, the queue is the way, and the extras are part of the note.
        let queue = await self.model()
        #expect(queue.route == .supportQueue)
    }

    // MARK: Reaching the queue

    @Test func theNoteGoesToTheQueueAndIsGoneFromTheDraft() async throws {
        let service = ScriptedFeedbackService()
        let store = InMemoryFeedbackDraftStore()
        let spoken = SpokenLines()
        let model = await model(service: service, store: store, spoken: spoken)
        model.message = "The hamper didn’t open Laundry."
        model.replyAddress = " lily@example.com "
        await model.finishWriting()
        #expect(try await store.draft()?.replyAddress == " lily@example.com ")

        await model.submit()
        guard case .sent(let note) = model.phase else {
            Issue.record("Not sent: \(model.phase)")
            return
        }
        #expect(note.replyAddress == "lily@example.com")
        #expect(model.receipt?.reference == "NK-0000AAAA")
        #expect(model.sendProblem == nil)
        await model.finishWriting()
        #expect(try await store.draft() == nil)
        #expect(spoken.lines == [FeedbackText.sentAnnouncement])
        let sent = await service.submissions()
        #expect(sent.count == 1)
        #expect(sent[0].note.message == "The hamper didn’t open Laundry.")
        #expect(sent[0].id.wholeMatch(of: /[A-Za-z0-9_-]{16,64}/) != nil)

        model.startOver()
        #expect(model.phase == .writing && model.message.isEmpty && model.replyAddress.isEmpty)
        #expect(model.receipt == nil && !model.includesClosetCounts && model.screenshot == nil)
    }

    @Test func aNoteThatCantGoStaysAsSheWroteItAndGoesWhenSheTapsSendAgain() async throws {
        let service = ScriptedFeedbackService(results: [.failure(.offline), .failure(.timedOut), .success(nil)])
        let store = InMemoryFeedbackDraftStore()
        let spoken = SpokenLines()
        let model = await model(service: service, store: store, spoken: spoken)
        model.kind = .idea
        model.message = "A laundry reminder, please."
        model.replyAddress = "lily@example.com"

        await model.submit()
        #expect(model.phase == .writing)
        #expect(model.sendProblem == .offline)
        #expect(model.message == "A laundry reminder, please." && model.kind == .idea)
        await model.finishWriting()
        let kept = try #require(try await store.draft())
        #expect(kept.message == "A laundry reminder, please." && kept.replyAddress == "lily@example.com")
        #expect(spoken.lines.last == FeedbackText.sendProblem(.offline, hasScreenshot: false))

        await model.submit()
        #expect(model.sendProblem == .timedOut)
        // Nothing was queued or retried on its own: only her two taps reached the service.
        #expect(await service.submissions().count == 2)

        await model.submit()
        #expect(model.sendProblem == nil)
        guard case .sent = model.phase else {
            Issue.record("Not sent")
            return
        }
        // The same note kept the same ID on all three tries, so a try whose answer was lost can't
        // become two tickets.
        let ids = Set(await service.submissions().map(\.id))
        #expect(ids.count == 1)
    }

    @Test func aChangedNoteGetsANewID() async {
        let service = ScriptedFeedbackService(results: [.failure(.offline), .success(nil)])
        let model = await model(service: service)
        model.message = "First words"
        await model.submit()
        model.message = "Better words"
        await model.submit()
        let ids = await service.submissions().map(\.id)
        #expect(ids.count == 2 && ids[0] != ids[1])
    }

    @Test func eachFailureHasWordsAndKeepsTheNote() async {
        let cases: [FeedbackSendProblem] = [
            .offline, .timedOut, .signedOut, .rateLimited(retryAfterSeconds: 300),
            .unavailable(retryAfterSeconds: 3600),
            .screenshotRefused, .updateRequired, .serverError, .rejected,
        ]
        for problem in cases {
            let model = await model(service: ScriptedFeedbackService(results: [.failure(problem)]))
            model.message = "Words"
            await model.submit()
            #expect(model.sendProblem == problem)
            #expect(model.phase == .writing && model.message == "Words")
            #expect(!FeedbackText.sendProblem(problem, hasScreenshot: false).isEmpty)
        }
        #expect(
            FeedbackText.sendProblem(.rateLimited(retryAfterSeconds: 300), hasScreenshot: false).contains("5 minutes"))
        #expect(FeedbackText.sendProblem(.screenshotRefused, hasScreenshot: true).contains("screenshot"))
        #expect(!FeedbackText.sendProblem(.screenshotRefused, hasScreenshot: false).contains("screenshot"))
    }

    @Test func leavingThePageStopsASendQuietlyAndTheNoteCanGoAgain() async {
        let clock = ManualClock()
        let service = ScriptedFeedbackService(hangsOn: clock)
        let model = await model(service: service)
        model.message = "Words"
        model.beginSubmit()
        await clock.waitForSleepers(1)
        #expect(model.phase == .sending)
        model.cancelSending()
        await model.finishSending()
        #expect(model.phase == .writing)
        #expect(model.sendProblem == nil)
        #expect(model.message == "Words")
    }

    @Test func anInvalidNoteIsntSentAndNamesWhatToFix() async {
        let service = ScriptedFeedbackService()
        let model = await model(service: service)
        await model.submit()
        #expect(model.problem == .empty)
        model.message = "Words"
        model.replyAddress = "lily at example"
        await model.submit()
        #expect(model.problem == .badReplyAddress)
        #expect(model.replyProblem == .badReplyAddress && model.messageProblem == nil)
        #expect(FeedbackText.problem(.badReplyAddress) == "That doesn’t look like an email address.")
        // The preview leaves out an address that can't be sent.
        let preview = model.preview
        #expect(preview?.contains("Reply address") == false)
        #expect(await service.submissions().isEmpty)
        model.replyAddress = "lily@example.com"
        #expect(model.problem == nil)
        #expect(model.preview?.contains("Reply address: lily@example.com") == true)
    }

    // MARK: What the page shows is what goes

    @Test func everyValueInTheRequestIsOnThePage() async throws {
        let service = ScriptedFeedbackService()
        let screenshots = ScriptedScreenshots()
        let model = await model(service: service, screenshots: screenshots)
        model.kind = .somethingWrong
        model.message = "The hamper didn’t open Laundry."
        model.replyAddress = "lily@example.com"
        model.includesDetails = true
        model.includesClosetCounts = true
        await model.finishCounting()
        await model.attachScreenshot(Data([1, 2, 3]))

        let preview = try #require(model.preview)
        let note = try model.note()
        #expect(!note.sentValues.isEmpty)
        for value in note.sentValues {
            #expect(preview.contains(value), "“\(value)” is sent but not shown")
        }
        #expect(preview.contains("Screenshot: 1 picture"))
        #expect(model.screenshot == note.screenshot)
        await model.submit()
        let sent = try #require(await service.submissions().first)
        #expect(sent.note == note)
        // Only the diagnostics she can see: the version, build, iOS and the model.
        #expect(sent.note.diagnostics == details)
        #expect(sent.note.closetCounts == counts)
    }

    @Test func nothingExtraRidesAlongByDefault() async throws {
        let service = ScriptedFeedbackService()
        let model = await model(service: service)
        model.message = "Words"
        await model.submit()
        let note = try #require(await service.submissions().first).note
        #expect(
            note.diagnostics == nil && note.closetCounts == nil && note.replyAddress == nil && note.screenshot == nil)
        #expect(note.sentValues == ["Words"])
    }

    // MARK: Closet counts

    @Test func closetCountsAreReadOnlyWhenTickedAndGoneWhenUntickedOrFailed() async throws {
        let model = await model()
        model.message = "Words"
        #expect(model.closetCounts == nil)
        model.includesClosetCounts = true
        await model.finishCounting()
        #expect(model.closetCounts == counts)
        #expect(model.preview?.contains("Closet size: 42 pieces, 9 looks, 2 suitcases") == true)
        model.includesClosetCounts = false
        #expect(model.closetCounts == nil)
        #expect(model.preview?.contains("Closet size") == false)

        // A closet that can't be counted unticks the switch instead of sending nothing silently.
        let broken = FeedbackModel(diagnostics: details, service: ScriptedFeedbackService(), closetCounts: { nil })
        await broken.checkRoute()
        broken.includesClosetCounts = true
        await broken.finishCounting()
        #expect(!broken.includesClosetCounts && broken.closetCounts == nil)
    }

    // MARK: Crash and speed details (31)

    private let health = DeviceHealthSummary(
        windowDays: 14, crashes: 2, hangs: 1, memoryExits: 1, longestHangMs: 2400, launchMedianMs: 450,
        peakMemoryMB: 310,
        crashKinds: [.init(exception: .badAccess, signal: .sigsegv, count: 2)])

    @Test func theSwitchShowsOnlyWhenThePhoneHasSomethingToShareAndTheNoteGoesToTheQueue() async {
        let health = health
        let nothing = await model()
        #expect(!nothing.offersDeviceHealth, "no diagnostics at all")
        let empty = await model(health: { nil })
        #expect(!empty.offersDeviceHealth, "nothing collected yet")
        let some = await model(health: { health })
        #expect(some.offersDeviceHealth)
        // The share sheet carries only her words and the app details, so no switch there.
        let signedOut = await model(service: ScriptedFeedbackService(canSend: false), health: { health })
        #expect(!signedOut.offersDeviceHealth)
    }

    @Test func itIsOffForEveryNoteAndNothingIsReadUntilSheTurnsItOn() async throws {
        let health = health
        let reads = Mutex(0)
        let service = ScriptedFeedbackService()
        let model = await model(
            service: service,
            health: {
                reads.withLock { $0 += 1 }
                return health
            })
        // Opening the page asked once whether there is anything to offer, and shows nothing of it.
        let afterOpening = reads.withLock { $0 }
        #expect(!model.includesDeviceHealth && model.deviceHealth == nil)
        model.message = "Words"
        #expect(model.preview?.contains("Crash") == false)
        await model.submit()
        let note = try #require(await service.submissions().first).note
        #expect(note.deviceHealth == nil && note.sentValues == ["Words"])
        #expect(reads.withLock { $0 } == afterOpening, "the summary was not read for a note that didn’t ask")
    }

    @Test func whatIsSentIsWhatIsShown() async throws {
        let health = health
        let service = ScriptedFeedbackService()
        let model = await model(service: service, health: { health })
        model.message = "It crashed when I opened Laundry."
        model.includesDeviceHealth = true
        await model.finishReadingDeviceHealth()
        #expect(model.deviceHealth == health)
        let preview = try #require(model.preview)
        let note = try model.note()
        #expect(note.deviceHealth == health)
        for value in note.sentValues {
            #expect(preview.contains(value), "“\(value)” is sent but not shown")
        }
        #expect(preview.contains("Crash and speed details, last 14 days:"))
        #expect(preview.contains("Crashes: 2. Hangs: 1."))
        #expect(preview.contains("Crash type: badAccess, sigsegv, 2 times."))
        await model.submit()
        let sent = try #require(await service.submissions().first)
        #expect(sent.note == note && sent.note.deviceHealth == health)
    }

    @Test func turningItOffTakesItBackOutAndItIsNotKeptInTheDraft() async throws {
        let health = health
        let store = InMemoryFeedbackDraftStore()
        let model = await model(store: store, health: { health })
        model.message = "Words"
        model.includesDeviceHealth = true
        await model.finishReadingDeviceHealth()
        #expect(try model.note().deviceHealth == health)
        model.includesDeviceHealth = false
        let withoutIt = try model.note()
        #expect(model.deviceHealth == nil && withoutIt.deviceHealth == nil)
        #expect(model.preview?.contains("Crash and speed") == false)
        model.includesDeviceHealth = true
        await model.finishReadingDeviceHealth()
        await model.finishWriting()
        // A new session starts with it off again: she decides for each note.
        let relaunched = await self.model(store: store, health: { health })
        await relaunched.restore()
        #expect(relaunched.message == "Words" && !relaunched.includesDeviceHealth && relaunched.deviceHealth == nil)
    }

    @Test func aSummaryThatDisappearsLeavesTheSwitchOffInsteadOfSendingNothing() async throws {
        let health = health
        let available = Mutex<DeviceHealthSummary?>(health)
        let model = await model(health: { available.withLock { $0 } })
        #expect(model.offersDeviceHealth)
        // Cleared (Delete my data) while the page was open.
        available.withLock { $0 = nil }
        model.includesDeviceHealth = true
        await model.finishReadingDeviceHealth()
        #expect(!model.includesDeviceHealth && model.deviceHealth == nil)
    }

    @Test func writeAnotherAndTheShareSheetNeverCarryIt() async throws {
        let health = health
        let model = await model(health: { health })
        model.message = "Words"
        model.includesDeviceHealth = true
        await model.finishReadingDeviceHealth()
        model.startOver()
        #expect(!model.includesDeviceHealth && model.deviceHealth == nil)
        let signedOut = await self.model(service: ScriptedFeedbackService(canSend: false), health: { health })
        signedOut.message = "Words"
        signedOut.includesDeviceHealth = true
        await signedOut.finishReadingDeviceHealth()
        #expect(try signedOut.note().deviceHealth == nil)
        #expect(signedOut.preview?.contains("Crash") == false)
    }

    // MARK: The screenshot

    @Test func aScreenshotIsPreparedShownAndRemovable() async throws {
        let screenshots = ScriptedScreenshots()
        let model = await model(screenshots: screenshots)
        await model.attachScreenshot(Data([9, 9]))
        #expect(model.screenshot?.data == Data([9, 9]))
        #expect(model.screenshotProblem == nil && !model.isPreparingScreenshot)
        model.removeScreenshot()
        #expect(model.screenshot == nil)

        screenshots.fail(with: .unreadable)
        await model.attachScreenshot(Data([1]))
        #expect(model.screenshot == nil && model.screenshotProblem == .unreadable)
        #expect(FeedbackText.screenshotProblem(.unreadable) == "That picture couldn’t be read. Try another.")
        screenshots.fail(with: .tooLarge)
        await model.attachScreenshot(Data([1]))
        #expect(model.screenshotProblem == .tooLarge)
        screenshots.fail(with: nil)
        await model.attachScreenshot(Data([1]))
        #expect(model.screenshotProblem == nil && model.screenshot != nil)
    }

    @Test func theScreenshotIsNeverKeptInTheDraft() async throws {
        let store = InMemoryFeedbackDraftStore()
        let model = await model(store: store)
        model.message = "Words"
        model.includesClosetCounts = true
        model.replyAddress = "lily@example.com"
        await model.attachScreenshot(Data([1, 2, 3]))
        await model.finishWriting()
        let kept = try #require(try await store.draft())
        #expect(kept == FeedbackDraft(message: "Words", replyAddress: "lily@example.com", includesClosetCounts: true))
        // After a relaunch the words, the address and the tick are back; the picture isn't.
        let relaunched = await self.model(store: store)
        await relaunched.restore()
        #expect(relaunched.message == "Words" && relaunched.replyAddress == "lily@example.com")
        #expect(relaunched.includesClosetCounts && relaunched.screenshot == nil)
    }

    /// The debug "sample screenshot" that the checkpoint attaches really does carry a place, a
    /// camera and a caption, so a clean result from the fake server means something.
    @Test func theSampleScreenshotCarriesMetadataToBeRemoved() {
        let sample = FeedbackSampleScreenshot.jpegWithMetadata()
        let found = DirtyPhoto.metadataDictionaries(in: sample)
        for kind in ["{Exif}", "{GPS}", "{TIFF}", "{IPTC}"] {
            #expect(found.contains { $0.hasPrefix(kind) }, "\(kind) missing: \(found)")
        }
        #expect(DirtyPhoto.pixelSize(of: sample)?.height == 2532)
    }
}

// MARK: Stand-ins

/// Counts what the model said aloud.
final class SpokenLines: Sendable {
    private let state = Mutex<[String]>([])
    var lines: [String] { state.withLock { $0 } }
    func add(_ line: String) { state.withLock { $0.append(line) } }
}

/// A support queue that answers as scripted and remembers what it was given. The last result
/// repeats once the script runs out.
actor ScriptedFeedbackService: FeedbackService {
    private var script: [Result<FeedbackReceipt?, FeedbackSendProblem>]
    private let signedIn: Bool
    private let clock: ManualClock?
    private var taken: [FeedbackSubmission] = []
    private var counter = 0

    init(canSend: Bool = true, results: [Result<FeedbackReceipt?, FeedbackSendProblem>] = [.success(nil)]) {
        signedIn = canSend
        script = results
        clock = nil
    }

    /// A queue that never answers: it waits on a clock nobody advances, until it is cancelled.
    init(hangsOn clock: ManualClock) {
        signedIn = true
        script = []
        self.clock = clock
    }

    func submissions() -> [FeedbackSubmission] { taken }

    func canSend() async -> Bool { signedIn }

    func send(_ submission: FeedbackSubmission) async throws(FeedbackSendProblem) -> FeedbackReceipt {
        taken.append(submission)
        if let clock {
            do { try await clock.sleep(for: .seconds(60)) } catch { throw .offline }
            throw .offline
        }
        let next = script.count > 1 ? script.removeFirst() : script[0]
        switch next {
        case .failure(let problem): throw problem
        case .success(let receipt):
            counter += 1
            return receipt
                ?? FeedbackReceipt(
                    reference: "NK-0000AAAA", receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    hasScreenshot: submission.note.screenshot != nil)
        }
    }
}

/// Prepares a "screenshot" without any image work: its bytes are the ones it was handed.
final class ScriptedScreenshots: FeedbackScreenshotPreparing, Sendable {
    private let failure = Mutex<FeedbackScreenshotProblem?>(nil)

    func fail(with problem: FeedbackScreenshotProblem?) { failure.withLock { $0 = problem } }

    func prepare(_ data: Data) async throws(FeedbackScreenshotProblem) -> FeedbackScreenshot {
        if let problem = failure.withLock({ $0 }) { throw problem }
        return FeedbackScreenshot(data: data, pixelWidth: 390, pixelHeight: 844)
    }
}
