import Foundation
import Models
import Observation

/// Report a problem on an AI result (Release, App Review Guideline 1.2): a stylist look or its why
/// line, an Ask stylist answer, or a try-on picture.
///
/// She picks a reason (four of them), may add a short note, and taps Send. It goes to the private
/// support queue as a report (`FeedbackService.sendReport`) with the result's IDs and when it was
/// made, never a provider or model (the backend adds those from its own records). No picture goes
/// unless she ticks Include the picture, which only a try-on picture offers, off every time. She
/// can also hide the result: once the report is sent, the screen that opened the sheet hides it.
/// Sending the same report again can't make a second ticket (`AIReportSubmission`).
@Observable
final class AIReportModel {
    enum Phase: Equatable {
        case writing
        case sending
        case sent(FeedbackReceipt)
    }

    let target: AIReportTarget
    /// What she may say it's about. Two when a look has a why line under it.
    let subjects: [AIReportSubject]
    /// The screen can hide this result (a look on Your looks, a picture in Saved Looks).
    let canHide: Bool

    var subject: AIReportSubject
    var reason: AIReportReason?
    var note = "" {
        didSet {
            if note.count > AIReport.noteMaximumCharacters {
                note = String(note.prefix(AIReport.noteMaximumCharacters))
            }
        }
    }
    /// Off every time the sheet opens. Only a try-on picture has a picture to include.
    var includesPicture = false
    var hides = false
    private(set) var phase = Phase.writing
    private(set) var problem: FeedbackSendProblem?
    /// She tapped Send without a reason.
    private(set) var needsReason = false

    @ObservationIgnored private var lastAttempt: AIReportSubmission?

    init(target: AIReportTarget, subjects: [AIReportSubject]? = nil, canHide: Bool) {
        self.target = target
        self.subjects = subjects ?? [target.subject]
        self.canHide = canHide
        subject = target.subject
    }

    var offersPicture: Bool { target.picture != nil }

    var isSending: Bool { phase == .sending }

    /// The four reasons, in the sheet's order.
    var reasons: [AIReportReason] { AIReportReason.allCases }

    /// Send: asks her to sign in if she isn't, includes the picture only if she ticked it, and
    /// leaves the report as she wrote it if it can't go. Returns true when it was sent.
    @discardableResult
    func send(with services: NookServices, signIn: SignInCheck) async -> Bool {
        guard phase == .writing else { return false }
        guard let reason else {
            needsReason = true
            return false
        }
        needsReason = false
        problem = nil
        guard await signIn(.report) else { return false }
        phase = .sending
        var picture: FeedbackScreenshot?
        if includesPicture, let reference = target.picture {
            do {
                guard let data = try await services.images.imageData(for: reference, maxPixelSize: 2_000) else {
                    return fail(.screenshotRefused)
                }
                picture = try await services.screenshots.prepare(data)
            } catch {
                return fail(.screenshotRefused)
            }
        }
        var aimed = target
        aimed.subject = subject
        let report = AIReport(target: aimed, reason: reason, note: note, picture: picture, hidden: hides && canHide)
        let submission =
            lastAttempt.flatMap { $0.report == report ? $0 : nil } ?? AIReportSubmission(report: report)
        lastAttempt = submission
        do {
            let receipt = try await services.feedback.sendReport(submission)
            phase = .sent(receipt)
            CloudProblemText.announce(AIReportText.sentTitle)
            return true
        } catch {
            return fail(error)
        }
    }

    private func fail(_ error: FeedbackSendProblem) -> Bool {
        phase = .writing
        problem = error
        CloudProblemText.announce(AIReportText.problem(error))
        return false
    }
}
