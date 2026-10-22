import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Networking

/// Send feedback (Phase 24d) through the real client and the fake backend: a note reaches the
/// queue, the request carries exactly what the page shows, a screenshot is audited for metadata,
/// a resend or a lost answer never makes a second ticket, the limits hold, and deleting the
/// account deletes the notes.
@Suite("Support notes")
struct FeedbackGatewayTests {
    /// One clock for the fake backend and the fake sign-in, which a test moves by hand.
    let time = Wall()
    let policy = RetryPolicy(requestTimeout: .seconds(60))
    let clock = ManualClock()
    let backend: FakeBackend
    let auth: FakeAuthProvider
    let account: GatewayAccountService
    let feedback: GatewayFeedbackService

    init() {
        let time = time
        let now: @Sendable () -> Date = { time.now }
        let backend = FakeBackend(now: now)
        let auth = FakeAuthProvider(subject: "lily", now: now)
        let policy = policy
        let clock = clock
        let client = APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth, policy: policy, clock: clock, sleep: { try await clock.skip($0) })
        self.backend = backend
        self.auth = auth
        self.account = GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0")
        self.feedback = GatewayFeedbackService(auth: auth, client: client)
    }

    func advance(_ seconds: TimeInterval) {
        time.advance(seconds)
    }

    func signIn() async throws {
        _ = try await account.signIn()
    }

    static let details = FeedbackDiagnostics(
        appVersion: "0.1", build: "14", systemVersion: "26.5", deviceModel: "iPhone13,2")

    static let health = DeviceHealthSummary(
        windowDays: 14, crashes: 2, hangs: 1, cpuExceptions: 0, diskWriteExceptions: 0, memoryExits: 1,
        watchdogExits: 0,
        longestHangMs: 2400, launchMedianMs: 450, peakMemoryMB: 310,
        crashKinds: [.init(exception: .badAccess, signal: .sigsegv, count: 2)])

    func note(
        _ message: String = "The hamper didn’t open Laundry.", details: Bool = false, reply: String? = nil,
        counts: Bool = false, health: Bool = false, screenshot: Data? = nil
    ) -> FeedbackNote {
        FeedbackNote(
            kind: .somethingWrong, message: message, diagnostics: details ? Self.details : nil, replyAddress: reply,
            closetCounts: counts ? FeedbackClosetCounts(pieces: 42, looks: 9, suitcases: 2) : nil,
            deviceHealth: health ? Self.health : nil,
            screenshot: screenshot.map { FeedbackScreenshot(data: $0, pixelWidth: 390, pixelHeight: 844) })
    }

    // MARK: Reaching the queue

    @Test func aNoteReachesTheQueueWithAReference() async throws {
        try await signIn()
        #expect(await feedback.canSend())
        let receipt = try await feedback.send(
            FeedbackSubmission(id: FeedbackSubmission.newID(), note: note(details: true, reply: "lily@example.com")))
        #expect(receipt.reference.wholeMatch(of: /NK-[0-9A-F]{8}/) != nil)
        #expect(!receipt.hasScreenshot)
        let ticket = try #require(backend.supportTickets.first)
        #expect(ticket.reference == receipt.reference)
        #expect(ticket.message == "The hamper didn’t open Laundry.")
        #expect(ticket.kind == "somethingWrong")
        #expect(ticket.replyTo == "lily@example.com")
        #expect(ticket.diagnostics?["deviceModel"] == "iPhone13,2")
        #expect(ticket.closetCounts == nil)
        #expect(ticket.screenshot == nil)
    }

    @Test func aNoteWithNothingExtraCarriesNothingExtra() async throws {
        try await signIn()
        _ = try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note()))
        let ticket = try #require(backend.supportTickets.first)
        #expect(ticket.replyTo == nil && ticket.diagnostics == nil && ticket.closetCounts == nil)
        #expect(ticket.screenshot == nil)
        let report = try #require(
            try JSONSerialization.jsonObject(with: backend.supportReport()) as? [String: Any])
        let last = try #require(report["last"] as? [String: Any])
        #expect(last["hasReplyAddress"] as? Bool == false)
        #expect(last["hasDiagnostics"] as? Bool == false)
        #expect(last["hasClosetCounts"] as? Bool == false)
        #expect(last["screenshot"] == nil)
    }

    @Test func theRequestCarriesExactlyWhatThePageShows() throws {
        // Every value in the request is one of the note's sentValues (what the page lists before
        // she sends), or the kind, the note's random ID or the picture's type and bytes.
        let picture = DirtyPhoto.jpeg(metadata: false)
        let full = note(details: true, reply: "lily@example.com", counts: true, health: true, screenshot: picture)
        let request = APIV1.FeedbackRequest(FeedbackSubmission(id: "sub_0123456789abcdef", note: full))
        let object = try #require(
            try JSONSerialization.jsonObject(with: APIV1.encoder().encode(request)) as? [String: Any])
        var leaves: [String] = []
        func collect(_ value: Any, path: String) {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary { collect(child, path: path + "/" + key) }
            } else if let list = value as? [Any] {
                for (index, child) in list.enumerated() { collect(child, path: path + "/\(index)") }
            } else {
                leaves.append("\(path)=\(value)")
            }
        }
        collect(object, path: "")
        let constants: Set<String> = [
            "/submissionId=sub_0123456789abcdef", "/kind=somethingWrong", "/attachment/contentType=image/jpeg",
            "/attachment/data=\(picture.base64EncodedString())",
        ]
        let carried = Set(leaves).subtracting(constants).map { String($0.split(separator: "=", maxSplits: 1)[1]) }
        #expect(carried.sorted() == full.sentValues.sorted())
        // The top-level keys are the contract's, and nothing else.
        #expect(
            Set(object.keys)
                == [
                    "submissionId", "kind", "message", "replyTo", "diagnostics", "closetCounts", "deviceHealth",
                    "attachment",
                ])
        // Without the extras, none of those keys is there.
        let plain = APIV1.FeedbackRequest(FeedbackSubmission(id: "sub_0123456789abcdef", note: note()))
        let plainObject = try #require(
            try JSONSerialization.jsonObject(with: APIV1.encoder().encode(plain)) as? [String: Any])
        #expect(Set(plainObject.keys) == ["submissionId", "kind", "message"])
        #expect(try APIV1.encoder().encode(request).count < APIV1.sendFeedback.maxBodyBytes)
    }

    // MARK: Crash and speed details (31)

    @Test func theApprovedSummaryReachesTheQueueAndNothingElseRidesAlong() async throws {
        try await signIn()
        _ = try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note(health: true)))
        _ = try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note("Second")))
        let tickets = backend.supportTickets
        #expect(tickets[0].deviceHealth == Self.health)
        #expect(tickets[1].deviceHealth == nil)
        let report = try #require(
            try JSONSerialization.jsonObject(with: backend.supportReport()) as? [String: Any])
        #expect((report["last"] as? [String: Any])?["hasDeviceHealth"] as? Bool == false)
    }

    @Test func theSummaryHasOnlyNumbersAndFixedNames() throws {
        let request = APIV1.FeedbackRequest(FeedbackSubmission(id: "sub_0123456789abcdef", note: note(health: true)))
        let object = try #require(
            try JSONSerialization.jsonObject(with: APIV1.encoder().encode(request)) as? [String: Any])
        let health = try #require(object["deviceHealth"] as? [String: Any])
        #expect(
            Set(health.keys) == [
                "windowDays", "crashes", "hangs", "cpuExceptions", "diskWriteExceptions", "memoryExits",
                "watchdogExits",
                "longestHangMs", "launchMedianMs", "peakMemoryMB", "crashKinds",
            ])
        for (name, value) in health where name != "crashKinds" { #expect(value is NSNumber, "\(name)") }
        let kinds = try #require(health["crashKinds"] as? [[String: Any]])
        #expect(Set(try #require(kinds.first).keys) == ["exception", "signal", "count"])
        // Empty lists and unset timings are left out, not sent as zero.
        let bare = APIV1.FeedbackRequest(
            FeedbackSubmission(
                id: "sub_0123456789abcdef",
                note: FeedbackNote(
                    kind: .idea, message: "Hi", deviceHealth: DeviceHealthSummary(windowDays: 3, crashes: 1))))
        let bareObject = try #require(
            try JSONSerialization.jsonObject(with: APIV1.encoder().encode(bare)) as? [String: Any])
        let bareHealth = try #require(bareObject["deviceHealth"] as? [String: Any])
        #expect(
            bareHealth["crashKinds"] == nil && bareHealth["longestHangMs"] == nil && bareHealth["peakMemoryMB"] == nil)
    }

    @Test func theFakeRefusesAnythingTheContractWould() async throws {
        try await signIn()
        func send(_ health: [String: Any]) async throws -> Int {
            let base: [String: Any] = [
                "submissionId": FeedbackSubmission.newID(), "kind": "idea", "message": "Hi", "deviceHealth": health,
            ]
            return try await post(base)
        }
        let good: [String: Any] = [
            "windowDays": 14, "crashes": 1, "hangs": 0, "cpuExceptions": 0, "diskWriteExceptions": 0, "memoryExits": 0,
            "watchdogExits": 0,
        ]
        #expect(try await send(good) == 202)
        #expect(try await send(good.merging(["stack": "0x1000 main"]) { $1 }) == 400)
        #expect(try await send(good.merging(["terminationReason": "Namespace SIGNAL"]) { $1 }) == 400)
        #expect(try await send(good.merging(["crashes": -1]) { $1 }) == 400)
        #expect(try await send(good.merging(["crashes": 1.5]) { $1 }) == 400)
        #expect(try await send(good.merging(["windowDays": 0]) { $1 }) == 400)
        #expect(
            try await send(
                good.merging(["crashKinds": [["exception": "EXC_BAD_ACCESS in Foo", "signal": "sigsegv", "count": 1]]])
                { $1 }) == 400)
        #expect(try await send(["windowDays": 14]) == 400)
        #expect(backend.supportTickets.count == 1)
    }

    /// Posts a body straight at the fake, as a client that wasn't this app would.
    private func post(_ body: [String: Any]) async throws -> Int {
        let session = APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self])
        var request = URLRequest(url: backend.baseURL.appending(path: "v1/feedback"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(try await auth.token(forceRefresh: false).value)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    // MARK: The screenshot

    @Test func theFakeFlagsMetadataInAPictureAndPassesACleanOne() async throws {
        try await signIn()
        let dirty = DirtyPhoto.jpeg()
        let found = DirtyPhoto.metadataDictionaries(in: dirty)
        for kind in ["{Exif}", "{GPS}", "{TIFF}", "{IPTC}"] {
            #expect(found.contains { $0.hasPrefix(kind) }, "The test picture has no \(kind): \(found)")
        }
        let sent = try await feedback.send(
            FeedbackSubmission(id: FeedbackSubmission.newID(), note: note(screenshot: dirty)))
        #expect(sent.hasScreenshot)
        let flagged = try #require(backend.supportTickets.last?.screenshot)
        for kind in ["{Exif}", "{GPS}", "{TIFF}", "{IPTC}"] {
            #expect(flagged.metadataDictionaries.contains { $0.hasPrefix(kind) }, "\(flagged.metadataDictionaries)")
        }

        let clean = DirtyPhoto.jpeg(metadata: false)
        advance(13 * 60)
        _ = try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note(screenshot: clean)))
        let passed = try #require(backend.supportTickets.last?.screenshot)
        #expect(passed.metadataDictionaries.isEmpty)
        #expect(passed.pixelWidth == 390 && passed.pixelHeight == 844)
        #expect(passed.data == clean)
    }

    @Test func aPictureThatIsntOneIsRefused() async throws {
        try await signIn()
        await #expect(throws: FeedbackSendProblem.screenshotRefused) {
            try await feedback.send(
                FeedbackSubmission(id: FeedbackSubmission.newID(), note: note(screenshot: Data("not a picture".utf8))))
        }
        #expect(backend.supportTickets.isEmpty)
    }

    // MARK: Sending again

    @Test func theSameNoteAgainGivesTheSameTicket() async throws {
        try await signIn()
        let submission = FeedbackSubmission(id: FeedbackSubmission.newID(), note: note())
        let first = try await feedback.send(submission)
        let again = try await feedback.send(submission)
        #expect(again.reference == first.reference)
        #expect(backend.supportTickets.count == 1)
        // A different note is a different ticket.
        advance(13 * 60)
        let other = try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note("Another")))
        #expect(other.reference != first.reference)
        #expect(backend.supportTickets.count == 2)
    }

    @Test func noConnectionLeavesNothingAndTheNextTryWorks() async throws {
        try await signIn()
        let submission = FeedbackSubmission(id: FeedbackSubmission.newID(), note: note())
        backend.setMode(.offline, times: 1)
        await #expect(throws: FeedbackSendProblem.offline) { try await feedback.send(submission) }
        #expect(backend.supportTickets.isEmpty)
        _ = try await feedback.send(submission)
        #expect(backend.supportTickets.count == 1)
    }

    @Test func aLostAnswerIsRetriedAndStillMakesOneTicket() async throws {
        try await signIn()
        // The server takes the note, then the answer never arrives; the client asks again with
        // the same submission ID and gets the first ticket back.
        backend.setMode(.answerLost, times: 1)
        let receipt = try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note()))
        #expect(backend.supportTickets.count == 1)
        #expect(backend.supportTickets[0].reference == receipt.reference)
    }

    // MARK: Limits

    @Test func aBurstIsSlowedDownAndWaitingBringsRoomBack() async throws {
        try await signIn()
        for index in 0..<5 {
            _ = try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note("Note \(index)")))
        }
        let problem = await #expect(throws: FeedbackSendProblem.self) {
            try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note("One too many")))
        }
        guard case .rateLimited(let seconds) = problem else {
            Issue.record("Not rate limited: \(String(describing: problem))")
            return
        }
        #expect(seconds > 0 && seconds <= 12 * 60)
        #expect(backend.supportTickets.count == 5)
        advance(Double(seconds) + 1)
        _ = try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note("Now it fits")))
        #expect(backend.supportTickets.count == 6)
    }

    @Test func tenNotesAndThreeScreenshotsADay() async throws {
        try await signIn()
        let picture = DirtyPhoto.jpeg(metadata: false)
        func send(_ screenshot: Data?) async throws {
            advance(13 * 60)
            _ = try await feedback.send(
                FeedbackSubmission(id: FeedbackSubmission.newID(), note: note(screenshot: screenshot)))
        }
        for _ in 0..<3 { try await send(picture) }
        await #expect(throws: FeedbackSendProblem.self) { try await send(picture) }
        for _ in 0..<7 { try await send(nil) }
        #expect(backend.supportTickets.count == 10)
        await #expect(throws: FeedbackSendProblem.self) { try await send(nil) }
        // A day after the first, there is room again.
        advance(24 * 3600)
        try await send(nil)
        #expect(backend.supportTickets.count == 11)
    }

    @Test func closedIntakeIsUnavailableButAResendStillGetsItsAnswer() async throws {
        try await signIn()
        let kept = FeedbackSubmission(id: FeedbackSubmission.newID(), note: note())
        let first = try await feedback.send(kept)
        backend.setSupportIntake(closed: true)
        let problem = await #expect(throws: FeedbackSendProblem.self) {
            try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note("New")))
        }
        guard case .unavailable(let seconds) = problem else {
            Issue.record("Not unavailable: \(String(describing: problem))")
            return
        }
        #expect(seconds == 3600)
        #expect(try await feedback.send(kept).reference == first.reference)
    }

    // MARK: Her account

    @Test func signedOutThereIsNoQueue() async throws {
        #expect(await !feedback.canSend())
        await #expect(throws: FeedbackSendProblem.signedOut) {
            try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note()))
        }
        #expect(backend.supportTickets.isEmpty)
    }

    @Test func deletingTheAccountDeletesTheNotes() async throws {
        try await signIn()
        _ = try await feedback.send(
            FeedbackSubmission(id: FeedbackSubmission.newID(), note: note(reply: "lily@example.com")))
        #expect(backend.holdsData(forSubject: "lily"))
        let deletion = try await account.deleteAccount()
        #expect(deletion.isComplete)
        #expect(backend.supportTickets.isEmpty)
        #expect(!backend.holdsData(forSubject: "lily"))
    }

    @Test func theUnavailableServiceCannotSend() async {
        let none = UnavailableFeedbackService()
        #expect(await !none.canSend())
        await #expect(throws: FeedbackSendProblem.signedOut) {
            try await none.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note()))
        }
    }

    // MARK: Reports about AI results (Release, guideline 1.2)

    static let actionID = "act_0f1e2d3c4b5a69788796a5b4c3d2e1f0"

    func report(_ subject: AIReportSubject, picture: Data? = nil, hidden: Bool = false) -> AIReportSubmission {
        let target = AIReportTarget(
            subject: subject, resultID: Self.actionID, actionID: Self.actionID,
            lookVersion: subject == .tryOnPicture ? nil : .simple, madeBy: .cloud,
            madeAt: Date(timeIntervalSince1970: 1_800_000_000), picture: .stored("photo-1"))
        return AIReportSubmission(
            report: AIReport(
                target: target, reason: .notMyClothes, note: "",
                picture: picture.map { FeedbackScreenshot(data: $0, pixelWidth: 390, pixelHeight: 844) },
                hidden: hidden))
    }

    @Test func aReportReachesTheQueueAsAnAIReportWithTheResultsIDsAndNoProvider() async throws {
        try await signIn()
        let receipt = try await feedback.sendReport(report(.look, hidden: true))
        #expect(receipt.reference.hasPrefix("NK-"))
        #expect(!receipt.hasScreenshot)
        let ticket = try #require(backend.supportTickets.last)
        #expect(ticket.kind == "aiReport")
        #expect(ticket.message == "No note added.")
        #expect(ticket.screenshot == nil)
        let block = try #require(ticket.aiReport)
        #expect(block["subject"] == "look")
        #expect(block["reason"] == "notMyClothes")
        #expect(block["actionId"] == Self.actionID)
        #expect(block["lookVersion"] == "simple")
        #expect(block["hidden"] == "true")
        #expect(Set(block.keys).isDisjoint(with: ["provider", "model"]))
    }

    @Test func theBodyCarriesThePictureOnlyWhenSheTickedIt() throws {
        let without =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(APIV1.FeedbackRequest(report(.tryOnPicture)))) as? [String: Any]
        #expect(without?["attachment"] == nil)
        #expect(without?["kind"] as? String == "aiReport")
        let with =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(APIV1.FeedbackRequest(report(.tryOnPicture, picture: Data([1, 2, 3])))))
            as? [String: Any]
        #expect((with?["attachment"] as? [String: Any])?["contentType"] as? String == "image/jpeg")
        // A look's report never carries one, even if one was handed in.
        let look = APIV1.FeedbackRequest(report(.look, picture: Data([1, 2, 3])))
        #expect(look.attachment == nil)
    }

    @Test func reportsHaveTheirOwnLimitAndLeaveNotesAlone() async throws {
        try await signIn()
        for _ in 0..<5 { _ = try await feedback.sendReport(report(.why)) }
        await #expect(throws: FeedbackSendProblem.self) { try await feedback.sendReport(report(.why)) }
        // Her support notes still go.
        _ = try await feedback.send(FeedbackSubmission(id: FeedbackSubmission.newID(), note: note()))
    }

    @Test func signedOutAReportCantGo() async {
        await #expect(throws: FeedbackSendProblem.signedOut) { try await feedback.sendReport(report(.look)) }
    }
}

/// The wall clock the fake backend and the fake sign-in share in these tests. It moves only when
/// a test advances it.
final class Wall: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { date.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { date.withLock { $0.addTimeInterval(seconds) } }

}
