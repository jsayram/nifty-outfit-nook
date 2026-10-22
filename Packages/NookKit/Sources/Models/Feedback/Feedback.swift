import Foundation

// Send feedback (Phase 14b, RD-10, PRD §22 "Private issue form" and "Diagnostics").
//
// A private note to the developer. Personal tier (DATA_MAP.md): she can type anything. Nothing is
// attached to it automatically: no closet, photos, measurements, looks or name. The app details
// are added only when she turns them on, and she sees exactly what goes before anything leaves.
//
// Stage A had no support queue, so the note left only through the system share sheet, to wherever
// she picked. Since Phase 24d, signed in, it goes to the private support queue (`FeedbackService`),
// with an optional reply address and an optional screenshot she chooses. Signed out, the share
// sheet is still how it goes, so Send feedback always works.

/// What the note is about (`feedback.html`).
public enum FeedbackKind: String, CaseIterable, Hashable, Sendable, Codable {
    case somethingWrong
    case idea
    case other
}

/// The app details she can choose to add: the version, iOS and device model. Never anything
/// about her.
public struct FeedbackDiagnostics: Hashable, Sendable, Codable {
    /// The app's version, like "0.1".
    public var appVersion: String
    /// The build number, like "14".
    public var build: String
    /// The iOS version, like "26.5".
    public var systemVersion: String
    /// The device model identifier, like "iPhone13,2" (an iPhone 12).
    public var deviceModel: String

    public init(appVersion: String, build: String, systemVersion: String, deviceModel: String) {
        self.appVersion = appVersion
        self.build = build
        self.systemVersion = systemVersion
        self.deviceModel = deviceModel
    }
}

/// How much is in her closet: three numbers, and only when she ticks the box. Never a name, a
/// picture or a description of a piece (24d). It helps to tell a slow closet from a small one.
public struct FeedbackClosetCounts: Hashable, Sendable, Codable {
    public var pieces: Int
    public var looks: Int
    public var suitcases: Int

    public init(pieces: Int, looks: Int, suitcases: Int) {
        self.pieces = pieces
        self.looks = looks
        self.suitcases = suitcases
    }
}

/// A screenshot she chose to attach, already shrunk and rewritten from its pixels alone (no EXIF,
/// no location, no time, no device; `PhotoCleaner` in Services). Kept in memory only: it is never
/// written to the draft, so closing the app drops it and she picks it again.
public struct FeedbackScreenshot: Hashable, Sendable {
    /// The cleaned picture, a JPEG.
    public var data: Data
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(data: Data, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// The most the backend accepts, in bytes (the contract's `limits.feedback.attachmentMaxBytes`).
    public static let maximumBytes = 600_000
}

/// A note ready to send: the kind, her words, and, only if she added them, the app details, a
/// reply address, her closet's counts and a screenshot.
public struct FeedbackNote: Hashable, Sendable {
    public var kind: FeedbackKind
    /// Her words, trimmed. Never empty, at most `FeedbackRules.maximumLength` characters.
    public var message: String
    public var diagnostics: FeedbackDiagnostics?
    /// Where to answer, if she gave an address (24d). Used for this note only.
    public var replyAddress: String?
    public var closetCounts: FeedbackClosetCounts?
    /// The phone's crash and speed counts, only if she turned on sharing them for this note (31).
    public var deviceHealth: DeviceHealthSummary?
    public var screenshot: FeedbackScreenshot?

    public init(
        kind: FeedbackKind, message: String, diagnostics: FeedbackDiagnostics? = nil, replyAddress: String? = nil,
        closetCounts: FeedbackClosetCounts? = nil, deviceHealth: DeviceHealthSummary? = nil,
        screenshot: FeedbackScreenshot? = nil
    ) {
        self.kind = kind
        self.message = message
        self.diagnostics = diagnostics
        self.replyAddress = replyAddress
        self.closetCounts = closetCounts
        self.deviceHealth = deviceHealth
        self.screenshot = screenshot
    }

    /// Every piece of text the app puts in the request, besides the kind and a random note ID:
    /// her words, the reply address, the app details and the closet counts as numbers. Send
    /// feedback shows each of these on the page before she sends, a test checks that the page does,
    /// and a networking test checks that the request carries these and nothing else (the picture
    /// is the screenshot she sees, byte for byte).
    public var sentValues: [String] {
        var values = [message]
        if let replyAddress { values.append(replyAddress) }
        if let diagnostics {
            values += [diagnostics.appVersion, diagnostics.build, diagnostics.systemVersion, diagnostics.deviceModel]
        }
        if let closetCounts {
            values += [String(closetCounts.pieces), String(closetCounts.looks), String(closetCounts.suitcases)]
        }
        if let deviceHealth { values += deviceHealth.sentValues }
        return values
    }
}

/// A note she started and hasn't sent: what it's about, her words as typed (not trimmed), and
/// whether she turned on the app details (Phase 21a). Kept so it's still there after the app
/// closes, until she sends it, clears it or deletes her data.
///
/// Data tier: **Personal** (free text, so it can hold anything she types).
///
/// Since Phase 24d the draft also keeps the reply address she typed and whether the closet counts
/// are ticked. A chosen screenshot is not kept (see `FeedbackScreenshot`). Drafts kept before 24d
/// read back with both as empty, and a draft without them writes exactly what it always did.
public struct FeedbackDraft: Hashable, Sendable, Codable {
    public var kind: FeedbackKind
    public var message: String
    public var includesDetails: Bool
    public var replyAddress: String
    public var includesClosetCounts: Bool

    public init(
        kind: FeedbackKind = .somethingWrong, message: String = "", includesDetails: Bool = false,
        replyAddress: String = "", includesClosetCounts: Bool = false
    ) {
        self.kind = kind
        self.message = message
        self.includesDetails = includesDetails
        self.replyAddress = replyAddress
        self.includesClosetCounts = includesClosetCounts
    }

    private enum CodingKeys: String, CodingKey {
        case kind, message, includesDetails, replyAddress, includesClosetCounts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(FeedbackKind.self, forKey: .kind)
        message = try container.decode(String.self, forKey: .message)
        includesDetails = try container.decode(Bool.self, forKey: .includesDetails)
        replyAddress = try container.decodeIfPresent(String.self, forKey: .replyAddress) ?? ""
        includesClosetCounts = try container.decodeIfPresent(Bool.self, forKey: .includesClosetCounts) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(message, forKey: .message)
        try container.encode(includesDetails, forKey: .includesDetails)
        if !replyAddress.isEmpty { try container.encode(replyAddress, forKey: .replyAddress) }
        if includesClosetCounts { try container.encode(true, forKey: .includesClosetCounts) }
    }

    /// Nothing worth keeping: no words, and everything else as a new note starts.
    public var isBlank: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Where the unsent Send feedback note is kept. One note at a time.
public protocol FeedbackDraftStore: ErasableStore {
    func draft() async throws(StoreError) -> FeedbackDraft?
    /// Replaces the note.
    func save(_ draft: FeedbackDraft) async throws(StoreError)
    /// Removes the note. Removing when there's none is fine.
    func discard() async throws(StoreError)
}

/// Why a note can't be sent yet.
public enum FeedbackProblem: Hashable, Sendable, Error {
    case empty
    case tooLong(maximum: Int)
    /// The reply address isn't an email address (24d).
    case badReplyAddress
}

/// The checks on a note.
public enum FeedbackRules {
    /// The mockup's limit. PRD §22 allows 2,000 for a public idea; a private note stays shorter.
    public static let maximumLength = 1000

    /// Checks the words she typed and builds the note. Diagnostics go in only when she turned
    /// them on, so the default is a note with nothing but her words.
    public static func note(
        kind: FeedbackKind, message: String, includeDiagnostics: Bool, diagnostics: FeedbackDiagnostics,
        replyAddress: String = "", closetCounts: FeedbackClosetCounts? = nil,
        deviceHealth: DeviceHealthSummary? = nil, screenshot: FeedbackScreenshot? = nil
    ) throws(FeedbackProblem) -> FeedbackNote {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard trimmed.count <= maximumLength else { throw .tooLong(maximum: maximumLength) }
        let address = replyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.isEmpty || isEmailAddress(address) else { throw .badReplyAddress }
        return FeedbackNote(
            kind: kind, message: trimmed, diagnostics: includeDiagnostics ? diagnostics : nil,
            replyAddress: address.isEmpty ? nil : address, closetCounts: closetCounts,
            deviceHealth: deviceHealth?.isWithinContract == true ? deviceHealth : nil, screenshot: screenshot)
    }

    /// The same shape the backend accepts (the contract's `replyTo` pattern): something, an @,
    /// a domain with a dot, no spaces or quotes, at most 254 characters.
    public static func isEmailAddress(_ text: String) -> Bool {
        text.count <= 254 && text.wholeMatch(of: /[^@\s<>"(),;:\\]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}/) != nil
    }
}
