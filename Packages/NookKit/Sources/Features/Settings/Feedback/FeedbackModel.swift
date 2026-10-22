import Foundation
import Models
import Observation

/// Send feedback (RD-10, `feedback.html`, PRD §22 "Private issue form").
///
/// She picks what it's about, writes her note, and can add the app details. The page always shows
/// exactly what would be sent.
///
/// Two ways it goes, chosen by `checkRoute()` when the page opens:
/// - **The support queue** (Phase 24d), when she's signed in on a backend: Send gives the note to
///   `FeedbackService`. She can also give a reply address, attach one screenshot she chooses, and
///   tick her closet's size (three numbers). Nothing else rides along. There is no queue on the
///   phone: a note that can't go stays in the draft, and goes when she taps Send again (Jose's
///   rule). Sending the same note again can't make a second ticket (`FeedbackSubmission`).
/// - **The share sheet**, when she isn't (the Stage A way): Send opens the system share sheet
///   with the note's text and nothing else, so she picks where it goes (Messages, Mail). Support
///   has to work for everyone, so this stays.
///
/// Nothing about her is ever added: no closet contents, photos, measurements, looks or name. The
/// app details are off until she turns them on, and they're lines she can read first.
///
/// One model lives at the root while the app runs, so a note she leaves half-written is still
/// there when she comes back, from the drawer or from Profile. Since Phase 21a the root's model
/// also keeps the note in a `FeedbackDraftStore`, so it's still there after the app closes, until
/// she sends it, clears it or deletes her data. Models made without a store (previews, snapshot
/// tests) keep it in memory.
@Observable
final class FeedbackModel {
    enum Phase: Equatable {
        case writing
        /// The share sheet is open with this text.
        case sharing(String)
        /// The note is on its way to the support queue.
        case sending
        /// She sent it somewhere. The page says thank you and shows what went.
        case sent(FeedbackNote)
    }

    /// Where Send takes the note.
    enum Route: Equatable {
        case shareSheet
        case supportQueue
    }

    private(set) var phase: Phase = .writing
    private(set) var route = Route.shareSheet
    /// Set when the support queue took the note.
    private(set) var receipt: FeedbackReceipt?
    /// Why the last try to reach the queue failed. The note is still in the draft.
    private(set) var sendProblem: FeedbackSendProblem?
    var kind: FeedbackKind = .somethingWrong {
        didSet { keep() }
    }
    var message = "" {
        didSet { keep() }
    }
    /// Off unless she turns it on (PRD §22, "Diagnostics").
    var includesDetails = false {
        didSet { keep() }
    }
    /// Where to answer, if she wants an answer (24d). Kept in the draft with the note.
    var replyAddress = "" {
        didSet { keep() }
    }
    /// Off unless she turns it on (24d). Turning it on reads the counts, which she sees on the page.
    var includesClosetCounts = false {
        didSet {
            if includesClosetCounts { readCounts() } else { closetCounts = nil }
            keep()
        }
    }
    /// The three numbers `includesClosetCounts` adds, as shown.
    private(set) var closetCounts: FeedbackClosetCounts?
    /// The screenshot she chose, cleaned. In memory only: it isn't kept in the draft.
    private(set) var screenshot: FeedbackScreenshot?
    private(set) var isPreparingScreenshot = false
    private(set) var screenshotProblem: FeedbackScreenshotProblem?
    /// True once she has tried to send, so problems show from then on, never while she starts.
    private(set) var triedToSend = false
    /// The lines "Include app details" would add, read once.
    let diagnostics: FeedbackDiagnostics
    /// Where the unsent note is kept, or `nil` to keep it in memory only.
    @ObservationIgnored private let store: (any FeedbackDraftStore)?
    /// The last write to the store, so writes land in the order she made the changes.
    @ObservationIgnored private var lastWrite: Task<Void, Never>?
    /// True while `restore` fills in a kept note, so that doesn't write it back.
    @ObservationIgnored private var isRestoring = false
    /// True once she has changed anything, so a kept note read late never replaces her typing.
    @ObservationIgnored private var hasChanged = false

    @ObservationIgnored private let service: any FeedbackService
    @ObservationIgnored private let screenshots: any FeedbackScreenshotPreparing
    @ObservationIgnored private let countCloset: (@Sendable () async -> FeedbackClosetCounts?)?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var countsTask: Task<Void, Never>?
    /// The last note tried and its ID. Sending the same note again uses the same ID, so a try
    /// whose answer was lost can't become two tickets; a changed note gets a new one.
    @ObservationIgnored private var lastAttempt: FeedbackSubmission?
    /// How a failure or a success is spoken. VoiceOver by default.
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    init(
        diagnostics: FeedbackDiagnostics? = nil, store: (any FeedbackDraftStore)? = nil,
        service: any FeedbackService = UnavailableFeedbackService(),
        screenshots: any FeedbackScreenshotPreparing = UnavailableScreenshotPreparer(),
        closetCounts: (@Sendable () async -> FeedbackClosetCounts?)? = nil,
        announce: @escaping @MainActor (String) -> Void = { CloudProblemText.announce($0) }
    ) {
        self.diagnostics = diagnostics ?? .current
        self.store = store
        self.service = service
        self.screenshots = screenshots
        self.countCloset = closetCounts
        self.announce = announce
    }

    /// The model the app keeps at the root: the draft store, the support queue, the screenshot
    /// maker, and a way to count her closet.
    convenience init(services: NookServices) {
        let closet = services.closet
        let looks = services.looks
        let suitcases = services.suitcases
        self.init(
            store: services.feedbackDrafts, service: services.feedback, screenshots: services.screenshots,
            closetCounts: {
                guard let pieces = try? await closet.garments().count, let made = try? await looks.looks().count,
                    let cases = try? await suitcases.suitcases().count
                else { return nil }
                return FeedbackClosetCounts(pieces: pieces, looks: made, suitcases: cases)
            })
    }

    /// Chooses the route: the support queue when she's signed in on a backend, the share sheet
    /// otherwise. Called when the page opens.
    func checkRoute() async {
        let canSend = await service.canSend()
        route = canSend ? .supportQueue : .shareSheet
    }

    private func readCounts() {
        guard let countCloset else { return }
        countsTask?.cancel()
        countsTask = Task { [weak self] in
            let counts = await countCloset()
            guard !Task.isCancelled, let self, self.includesClosetCounts else { return }
            if let counts {
                self.closetCounts = counts
            } else {
                // A closet that can't be counted: the switch goes back off rather than being on
                // with nothing to send.
                self.includesClosetCounts = false
            }
        }
    }

    /// Waits for the closet count she asked for. For tests.
    func finishCounting() async {
        await countsTask?.value
    }

    /// Fills in the note she left unsent last time, if there is one and she hasn't started a new
    /// one since. A store that can't be read leaves the page empty, as on a first visit.
    func restore() async {
        guard let store, let kept = try? await store.draft(), !hasChanged, phase == .writing else { return }
        isRestoring = true
        kind = kept.kind
        message = kept.message
        includesDetails = kept.includesDetails
        replyAddress = kept.replyAddress
        includesClosetCounts = kept.includesClosetCounts
        isRestoring = false
    }

    /// Writes the note as it stands, or removes it when there's nothing in it. Each write waits
    /// for the one before, so the last change is the one kept. A failed write is ignored: the
    /// note is still on screen, and the next change tries again.
    private func keep() {
        guard !isRestoring else { return }
        hasChanged = true
        guard let store, phase == .writing else { return }
        let draft = FeedbackDraft(
            kind: kind, message: message, includesDetails: includesDetails,
            replyAddress: replyAddress, includesClosetCounts: includesClosetCounts)
        write(draft.isBlank ? nil : draft, to: store)
    }

    private func write(_ draft: FeedbackDraft?, to store: any FeedbackDraftStore) {
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            if let draft {
                try? await store.save(draft)
            } else {
                try? await store.discard()
            }
        }
    }

    /// Waits for the writes started so far. For tests.
    func finishWriting() async {
        await lastWrite?.value
    }

    /// The note as it stands, or why it can't be sent yet.
    func note() throws(FeedbackProblem) -> FeedbackNote {
        // The queue takes more than the share sheet: a reply address, the closet's size and a
        // screenshot. On the share sheet route those are not part of the note.
        let queue = route == .supportQueue
        return try FeedbackRules.note(
            kind: kind, message: message, includeDiagnostics: includesDetails, diagnostics: diagnostics,
            replyAddress: queue ? replyAddress : "", closetCounts: queue ? closetCounts : nil,
            screenshot: queue ? screenshot : nil)
    }

    /// Why the note can't go yet, once she has tried to send. It goes away as she fixes it.
    var problem: FeedbackProblem? {
        guard triedToSend else { return nil }
        do {
            _ = try note()
            return nil
        } catch {
            return error
        }
    }

    /// The problem with her words, which shows under the note's field.
    var messageProblem: FeedbackProblem? {
        problem == .badReplyAddress ? nil : problem
    }

    /// The problem with the reply address, which shows under its field.
    var replyProblem: FeedbackProblem? {
        problem == .badReplyAddress ? .badReplyAddress : nil
    }

    /// Exactly what Send would hand to the share sheet or the queue, or `nil` while there's
    /// nothing to send. A reply address that isn't one yet is left out, since it can't be sent.
    var preview: String? {
        if let note = try? note() { return FeedbackComposer.text(note) }
        guard route == .supportQueue else { return nil }
        let withoutAddress = try? FeedbackRules.note(
            kind: kind, message: message, includeDiagnostics: includesDetails, diagnostics: diagnostics,
            closetCounts: closetCounts, screenshot: screenshot)
        return withoutAddress.map(FeedbackComposer.text)
    }

    /// Send: checks the note, then opens the share sheet with its text. Returns false and shows
    /// the problem when it can't go yet.
    @discardableResult
    func send() -> Bool {
        triedToSend = true
        guard let note = try? note() else { return false }
        phase = .sharing(FeedbackComposer.text(note))
        return true
    }

    /// Shows the problems with the note from now on, without sending (the page's Send tapped
    /// while the note can't go).
    func markTriedToSend() {
        triedToSend = true
    }

    /// Send to the support queue (24d). Returns when the note went or failed; a failure leaves the
    /// note as she wrote it and says why in `sendProblem`.
    func submit() async {
        triedToSend = true
        guard route == .supportQueue, phase == .writing, let note = try? note() else { return }
        let submission: FeedbackSubmission
        if let earlier = lastAttempt, earlier.note == note {
            submission = earlier
        } else {
            submission = FeedbackSubmission(id: FeedbackSubmission.newID(), note: note)
        }
        lastAttempt = submission
        sendProblem = nil
        phase = .sending
        do {
            let receipt = try await service.send(submission)
            guard phase == .sending else { return }
            self.receipt = receipt
            phase = .sent(note)
            lastAttempt = nil
            // Sent, so there's no unsent note to keep any more.
            if let store { write(nil, to: store) }
            announce(FeedbackText.sentAnnouncement)
        } catch {
            guard phase == .sending else { return }
            phase = .writing
            // Leaving the page cancels the try quietly; the note is safe to send again.
            guard !Task.isCancelled else { return }
            sendProblem = error
            announce(FeedbackText.sendProblem(error, hasScreenshot: note.screenshot != nil))
        }
    }

    /// Send to the support queue without waiting, as the page's button does. Leaving the page
    /// calls `cancelSending()`.
    func beginSubmit() {
        guard phase == .writing else { return }
        sendTask = Task { [weak self] in await self?.submit() }
    }

    /// Stops a send in progress, quietly. The note stays as it was and can be sent again.
    func cancelSending() {
        sendTask?.cancel()
        if phase == .sending { phase = .writing }
    }

    /// Waits for the send the button started. For tests.
    func finishSending() async {
        await sendTask?.value
    }

    // MARK: The screenshot

    /// Shrinks and cleans the picture she chose, then attaches it. A picture that can't be read
    /// or is too large says so and leaves the page as it was.
    func attachScreenshot(_ data: Data) async {
        screenshotProblem = nil
        isPreparingScreenshot = true
        defer { isPreparingScreenshot = false }
        do {
            screenshot = try await screenshots.prepare(data)
        } catch {
            screenshotProblem = error
        }
    }

    /// She changed her mind about the picture, or about the whole note.
    func removeScreenshot() {
        screenshot = nil
        screenshotProblem = nil
    }

    /// The share sheet closed. `completed` is true when she sent or saved it somewhere.
    func shareFinished(completed: Bool) {
        guard case .sharing = phase else { return }
        if completed, let note = try? note() {
            phase = .sent(note)
            // Sent, so there's no unsent note to keep any more.
            if let store { write(nil, to: store) }
        } else {
            phase = .writing
        }
    }

    /// Write another: an empty note, details off again.
    func startOver() {
        sendTask?.cancel()
        sendTask = nil
        phase = .writing
        kind = .somethingWrong
        message = ""
        includesDetails = false
        replyAddress = ""
        includesClosetCounts = false
        screenshot = nil
        screenshotProblem = nil
        receipt = nil
        sendProblem = nil
        lastAttempt = nil
        triedToSend = false
    }
}
