import Foundation

// Send feedback (Phase 14b, RD-10, PRD §22 "Private issue form" and "Diagnostics").
//
// A private note to the developer. Personal tier (DATA_MAP.md): she can type anything. Nothing is
// attached to it automatically: no closet, photos, measurements, looks or name. The app details
// are added only when she turns them on, and she sees exactly what goes before anything leaves.
//
// Stage A has no support queue, so the note leaves only through the system share sheet, to
// wherever she picks. The real private support queue needs a backend phase (DATA_MAP open points).

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

/// A note ready to send: the kind, her words, and the app details only if she added them.
public struct FeedbackNote: Hashable, Sendable {
    public var kind: FeedbackKind
    /// Her words, trimmed. Never empty, at most `FeedbackRules.maximumLength` characters.
    public var message: String
    public var diagnostics: FeedbackDiagnostics?

    public init(kind: FeedbackKind, message: String, diagnostics: FeedbackDiagnostics? = nil) {
        self.kind = kind
        self.message = message
        self.diagnostics = diagnostics
    }
}

/// Why a note can't be sent yet.
public enum FeedbackProblem: Hashable, Sendable, Error {
    case empty
    case tooLong(maximum: Int)
}

/// The checks on a note.
public enum FeedbackRules {
    /// The mockup's limit. PRD §22 allows 2,000 for a public idea; a private note stays shorter.
    public static let maximumLength = 1000

    /// Checks the words she typed and builds the note. Diagnostics go in only when she turned
    /// them on, so the default is a note with nothing but her words.
    public static func note(
        kind: FeedbackKind, message: String, includeDiagnostics: Bool, diagnostics: FeedbackDiagnostics
    ) throws(FeedbackProblem) -> FeedbackNote {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard trimmed.count <= maximumLength else { throw .tooLong(maximum: maximumLength) }
        return FeedbackNote(kind: kind, message: trimmed, diagnostics: includeDiagnostics ? diagnostics : nil)
    }
}
