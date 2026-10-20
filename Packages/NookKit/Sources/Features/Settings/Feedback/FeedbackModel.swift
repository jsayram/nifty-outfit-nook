import Foundation
import Models
import Observation

/// Send feedback (RD-10, `feedback.html`, PRD §22 "Private issue form").
///
/// She picks what it's about, writes her note, and can add the app details. The page always shows
/// exactly what would be sent, and Send opens the system share sheet with that text and nothing
/// else, so she picks where it goes (Messages, Mail). The app sends nothing itself: Stage A has no
/// support queue (DATA_MAP.md, open points).
///
/// Nothing about her is ever added: no closet, photos, measurements, looks or name. The app
/// details are off until she turns them on, and they're three lines she can read first.
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
        /// She sent it somewhere. The page says thank you and shows what went.
        case sent(FeedbackNote)
    }

    private(set) var phase: Phase = .writing
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

    init(diagnostics: FeedbackDiagnostics? = nil, store: (any FeedbackDraftStore)? = nil) {
        self.diagnostics = diagnostics ?? .current
        self.store = store
    }

    /// Fills in the note she left unsent last time, if there is one and she hasn't started a new
    /// one since. A store that can't be read leaves the page empty, as on a first visit.
    func restore() async {
        guard let store, let kept = try? await store.draft(), !hasChanged, phase == .writing else { return }
        isRestoring = true
        kind = kept.kind
        message = kept.message
        includesDetails = kept.includesDetails
        isRestoring = false
    }

    /// Writes the note as it stands, or removes it when there's nothing in it. Each write waits
    /// for the one before, so the last change is the one kept. A failed write is ignored: the
    /// note is still on screen, and the next change tries again.
    private func keep() {
        guard !isRestoring else { return }
        hasChanged = true
        guard let store, phase == .writing else { return }
        let draft = FeedbackDraft(kind: kind, message: message, includesDetails: includesDetails)
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
        try FeedbackRules.note(
            kind: kind, message: message, includeDiagnostics: includesDetails, diagnostics: diagnostics)
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

    /// Exactly what Send would hand to the share sheet, or `nil` while there's nothing to send.
    var preview: String? {
        (try? note()).map(FeedbackComposer.text)
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
        phase = .writing
        kind = .somethingWrong
        message = ""
        includesDetails = false
        triedToSend = false
    }
}
