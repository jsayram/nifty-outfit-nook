import Foundation

// Report a problem on an AI result (Release, App Review Guideline 1.2): a look, its why line, an
// Ask stylist answer or a try-on picture. It goes to the private support queue as a note of kind
// `aiReport` (contract `POST /v1/feedback`), with the result's IDs and no provider or model: the
// backend adds those from its own record of the action. No picture goes unless she ticks Include
// the picture, and only a try-on picture can carry one.

/// What she is reporting.
public enum AIReportSubject: String, Hashable, Sendable, CaseIterable {
    /// A look the stylist made.
    case look
    /// The stylist's one-line reason under a look.
    case why
    /// An Ask stylist answer.
    case askAnswer
    /// A try-on picture.
    case tryOnPicture
}

/// Why she is reporting it. The four reasons on the sheet.
public enum AIReportReason: String, Hashable, Sendable, CaseIterable {
    case wrongOrOffensive
    case notMyClothes
    case looksWrongOnMe
    case other
}

/// Who made the result: the cloud, Apple's on-device model, or Quick ideas on the phone.
public enum AIReportMaker: String, Hashable, Sendable {
    case cloud
    case onDevice
    case phone

    public init(_ lane: StylistLane?) {
        switch lane {
        case .cloud, nil: self = .cloud
        case .onDevice: self = .onDevice
        case .rules: self = .phone
        }
    }
}

/// The result a report is about, as the app knows it. Never a provider or a model.
public struct AIReportTarget: Hashable, Sendable {
    public var subject: AIReportSubject
    /// The result's own ID: the stylist's result, or the picture.
    public var resultID: String
    /// The server's ID for the paid action that made it, when the app knows it.
    public var actionID: String?
    public var lookVersion: LookVersion?
    public var madeBy: AIReportMaker
    public var madeAt: Date
    /// A try-on picture's image, which she may choose to include. `nil` for everything else.
    public var picture: PhotoReference?

    public init(
        subject: AIReportSubject, resultID: String, actionID: String? = nil, lookVersion: LookVersion? = nil,
        madeBy: AIReportMaker, madeAt: Date, picture: PhotoReference? = nil
    ) {
        self.subject = subject
        self.resultID = resultID
        self.actionID = actionID.flatMap { Self.isActionID($0) ? $0 : nil }
        self.lookVersion = lookVersion
        self.madeBy = madeBy
        self.madeAt = madeAt
        self.picture = subject == .tryOnPicture ? picture : nil
    }

    /// The server's action IDs look like `act_` and 32 hex digits. Since this release a cloud
    /// result's ID is its action's ID (`CloudStylist`, `AIJobs`), so it's found from the result.
    public static func isActionID(_ text: String) -> Bool {
        text.wholeMatch(of: /act_[0-9a-f]{32}/) != nil
    }

    /// A stylist look (or its why line) from a result on Your looks.
    public static func look(
        _ look: Look, result: StyleResult, subject: AIReportSubject = .look
    ) -> AIReportTarget {
        let id = result.id.rawValue
        return AIReportTarget(
            subject: subject, resultID: id, actionID: id, lookVersion: look.version,
            madeBy: AIReportMaker(result.madeBy), madeAt: result.createdAt)
    }

    /// A try-on picture. Only a real one is reported: a simulated picture is drawn on the phone.
    public static func picture(_ picture: TryOnPicture) -> AIReportTarget {
        let id = picture.id.rawValue
        var image: PhotoReference?
        if case .generated(let photo) = picture.image { image = photo }
        return AIReportTarget(
            subject: .tryOnPicture, resultID: id, actionID: id, madeBy: .cloud, madeAt: picture.createdAt,
            picture: image)
    }
}

/// One report, as she sends it.
public struct AIReport: Hashable, Sendable {
    /// Her note is short: the reasons say most of it.
    public static let noteMaximumCharacters = 500

    public var target: AIReportTarget
    public var reason: AIReportReason
    /// Her own words, trimmed. Empty when she wrote nothing.
    public var note: String
    /// The picture, cleaned like a screenshot, only when she ticked Include the picture.
    public var picture: FeedbackScreenshot?
    /// She also hid the result.
    public var hidden: Bool

    public init(
        target: AIReportTarget, reason: AIReportReason, note: String = "", picture: FeedbackScreenshot? = nil,
        hidden: Bool = false
    ) {
        self.target = target
        self.reason = reason
        self.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.noteMaximumCharacters))
        self.picture = target.subject == .tryOnPicture ? picture : nil
        self.hidden = hidden
    }

    /// The note's text for the queue, which always has one: her words, or a plain line when she
    /// wrote none.
    public var message: String {
        note.isEmpty ? "No note added." : note
    }
}

/// A report with the ID that makes sending it again safe, like `FeedbackSubmission`.
public struct AIReportSubmission: Hashable, Sendable {
    public var id: String
    public var report: AIReport

    public init(id: String = FeedbackSubmission.newID(), report: AIReport) {
        self.id = id
        self.report = report
    }
}

extension FeedbackService {
    /// A service that predates reports can't send one: it says so as signed out, and the sheet
    /// keeps the report as she wrote it.
    public func sendReport(_ submission: AIReportSubmission) async throws(FeedbackSendProblem) -> FeedbackReceipt {
        throw .signedOut
    }
}
