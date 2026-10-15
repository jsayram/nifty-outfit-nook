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
/// there when she comes back, from the drawer or from Profile. It's in memory only, like every
/// Stage A draft, and Delete my data starts a new one.
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
    var kind: FeedbackKind = .somethingWrong
    var message = ""
    /// Off unless she turns it on (PRD §22, "Diagnostics").
    var includesDetails = false
    /// True once she has tried to send, so problems show from then on, never while she starts.
    private(set) var triedToSend = false
    /// The lines "Include app details" would add, read once.
    let diagnostics: FeedbackDiagnostics

    init(diagnostics: FeedbackDiagnostics? = nil) {
        self.diagnostics = diagnostics ?? .current
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
        } else {
            phase = .writing
        }
    }

    /// Write another: an empty note, details off again.
    func startOver() {
        kind = .somethingWrong
        message = ""
        includesDetails = false
        triedToSend = false
        phase = .writing
    }
}
