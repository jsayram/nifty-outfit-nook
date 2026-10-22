import Foundation

// Sending a note to the private support queue (Phase 24d, contract `POST /v1/feedback`).
//
// Signed in, Send feedback hands the note to a `FeedbackService`. There is no queue on the phone
// (Jose's rule, as for Phase 26): a note that can't go stays in the draft, exactly as she wrote
// it, and goes when she taps Send again. Signed out, or with no backend at all, `canSend` is false
// and the page keeps using the share sheet.

/// A note and the random ID that makes sending it again safe: the backend returns the same ticket
/// for the same ID instead of making a second one. A new ID is made when the note changes.
public struct FeedbackSubmission: Hashable, Sendable {
    public var id: String
    public var note: FeedbackNote

    public init(id: String, note: FeedbackNote) {
        self.id = id
        self.note = note
    }

    /// A fresh ID: 36 letters, digits and underscores, which the contract accepts (16 to 64).
    public static func newID() -> String {
        "sub_" + UUID().uuidString.replacing("-", with: "").lowercased()
    }
}

/// What the support queue gives back: a short reference she can quote, and when it arrived.
public struct FeedbackReceipt: Hashable, Sendable {
    /// Like "NK-7F3A9C21".
    public var reference: String
    public var receivedAt: Date
    public var hasScreenshot: Bool

    public init(reference: String, receivedAt: Date, hasScreenshot: Bool) {
        self.reference = reference
        self.receivedAt = receivedAt
        self.hasScreenshot = hasScreenshot
    }
}

/// Why a note didn't go, in the terms the page needs to explain it.
public enum FeedbackSendProblem: Error, Hashable, Sendable {
    /// No connection. The note is still in the draft.
    case offline
    case timedOut
    /// Not signed in any more (the session ended).
    case signedOut
    /// She has sent a lot of notes. Try again after this many seconds.
    case rateLimited(retryAfterSeconds: Int)
    /// Sending notes is paused or busy on the server. Try again later.
    case unavailable(retryAfterSeconds: Int?)
    /// The server couldn't use the picture. Send without it, or choose another.
    case screenshotRefused
    /// This version of the app is too old for the server.
    case updateRequired
    case serverError
    /// The server's answer didn't match the contract, or it rejected the note as malformed.
    case rejected
}

/// Where Send feedback sends a note when she's signed in.
public protocol FeedbackService: Sendable {
    /// True when notes go to the support queue: signed in on a backend. False otherwise, and then
    /// Send feedback uses the share sheet.
    func canSend() async -> Bool
    /// Sends the note. Safe to repeat with the same submission ID.
    func send(_ submission: FeedbackSubmission) async throws(FeedbackSendProblem) -> FeedbackReceipt
}

/// No support queue: what screens get when nothing configured one. Send feedback uses the share sheet.
public struct UnavailableFeedbackService: FeedbackService {
    public init() {}
    public func canSend() async -> Bool { false }
    public func send(_ submission: FeedbackSubmission) async throws(FeedbackSendProblem) -> FeedbackReceipt {
        throw .signedOut
    }
}

/// Why a picture she chose can't be attached.
public enum FeedbackScreenshotProblem: Error, Hashable, Sendable {
    /// Not a picture the phone can read.
    case unreadable
    /// Still too big after shrinking it as far as the app will.
    case tooLarge
}

/// Turns the picture she chose into the cleaned, small one that is sent and shown: upright, as a
/// JPEG, without its metadata (SECURITY_STANDARD §4), within `FeedbackScreenshot.maximumBytes`.
/// `ScreenshotPreparer` in Services does it with `PhotoCleaner`.
public protocol FeedbackScreenshotPreparing: Sendable {
    func prepare(_ data: Data) async throws(FeedbackScreenshotProblem) -> FeedbackScreenshot
}

/// No preparer: every picture is unreadable, so a screenshot can't be attached.
public struct UnavailableScreenshotPreparer: FeedbackScreenshotPreparing {
    public init() {}
    public func prepare(_ data: Data) async throws(FeedbackScreenshotProblem) -> FeedbackScreenshot {
        throw .unreadable
    }
}

/// The app's support page on the website, the one the App Store's Support URL points to. The app
/// never contains an email address (STACK.md); the page has it. Read from the Info.plist key
/// `NookSupportURL`, which comes from `NOOK_SUPPORT_URL` in Configs/Base.xcconfig. The default is
/// a placeholder until Phase 35b publishes the page.
public struct SupportLinks: Sendable, Equatable {
    public static let infoKey = "NookSupportURL"
    /// The address the website's support page is expected to have. A placeholder: the page is
    /// still to be published (compliance/SUPPORT_PAGE_OUTLINE.md).
    public static let placeholder: URL = {
        guard let url = URL(string: "https://niftyoutfitnook.pages.dev/support") else {
            preconditionFailure("The support page's address is written wrong")
        }
        return url
    }()

    public var supportPage: URL

    public init(supportPage: URL = SupportLinks.placeholder) {
        self.supportPage = supportPage
    }

    /// Reads the Info.plist value, ignoring an empty or unexpanded "$(...)" one and anything that
    /// isn't an https address without a query.
    public init(info: [String: Any]) {
        let text = (info[Self.infoKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty, !text.contains("$("), let url = URL(string: text), url.scheme == "https",
            url.host() != nil, url.query() == nil
        {
            supportPage = url
        } else {
            supportPage = Self.placeholder
        }
    }
}
