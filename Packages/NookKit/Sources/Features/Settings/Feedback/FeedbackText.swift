import Foundation
import Models

/// Turns a note into the exact text Send hands to the share sheet. The page shows this same text
/// before she sends, so what she reads is what goes.
///
/// It's built from the note alone: her words, what it's about, and the app details if she added
/// them. Nothing else is passed in, so nothing about her closet, body, looks or name can be added.
nonisolated enum FeedbackComposer {
    static func text(_ note: FeedbackNote) -> String {
        var lines = [
            FeedbackText.heading,
            FeedbackText.aboutLine(note.kind),
            "",
            note.message,
        ]
        if let details = note.diagnostics {
            lines.append("")
            lines.append(contentsOf: FeedbackText.detailLines(details))
        }
        return lines.joined(separator: "\n")
    }

    /// The subject Mail uses.
    static var subject: String { FeedbackText.heading }
}

/// The words on Send feedback (`feedback.html`).
nonisolated enum FeedbackText {
    static var heading: String {
        String(
            localized: "Nifty Outfit Nook feedback", bundle: .module,
            comment: "Send feedback: the first line of the note, and the email subject")
    }

    static func aboutLine(_ kind: FeedbackKind) -> String {
        String(
            localized: "About: \(kind.title)", bundle: .module,
            comment: "Send feedback: the note's second line, with what it's about")
    }

    /// The three lines "Include app details" adds, exactly as they're sent.
    static func detailLines(_ details: FeedbackDiagnostics) -> [String] {
        [
            String(
                localized: "App version: \(details.appVersion) (\(details.build))", bundle: .module,
                comment: "Send feedback: app details line, version and build"),
            String(
                localized: "iOS: \(details.systemVersion)", bundle: .module,
                comment: "Send feedback: app details line, the iOS version"),
            String(
                localized: "Device: \(details.deviceModel)", bundle: .module,
                comment: "Send feedback: app details line, the model identifier such as iPhone13,2"),
        ]
    }

    static var kindHeader: String {
        String(localized: "What is it about?", bundle: .module, comment: "Send feedback: above the kind chips")
    }

    /// The field's name, which follows the kind (`feedback.html`).
    static func messageLabel(_ kind: FeedbackKind) -> String {
        switch kind {
        case .somethingWrong:
            String(localized: "What happened?", bundle: .module, comment: "Send feedback: the field's name")
        case .idea:
            String(localized: "What’s your idea?", bundle: .module, comment: "Send feedback: the field's name")
        case .other:
            String(
                localized: "What would you like to say?", bundle: .module,
                comment: "Send feedback: the field's name")
        }
    }

    static var messagePrompt: String {
        String(
            localized: "For example: the hamper didn’t open Laundry.", bundle: .module,
            comment: "Send feedback: the empty field's prompt")
    }

    static var messageHint: String {
        String(
            localized:
                "Keep it about the app. There’s no need to add your measurements, photos or closet details.",
            bundle: .module, comment: "Send feedback: under the field")
    }

    static func problem(_ problem: FeedbackProblem) -> String {
        switch problem {
        case .empty:
            String(
                localized: "Write a few words to send the note.", bundle: .module,
                comment: "Send feedback: the note is empty")
        case .tooLong(let maximum):
            String(
                localized: "Keep it to \(maximum) characters or fewer.", bundle: .module,
                comment: "Send feedback: the note is too long")
        }
    }

    static var detailsRow: String {
        String(localized: "Include app details", bundle: .module, comment: "Send feedback: the switch")
    }

    static var detailsRowOff: String {
        String(
            localized: "Off unless you turn it on.", bundle: .module,
            comment: "Send feedback: under the Include app details switch")
    }

    static var detailsRowOn: String {
        String(
            localized: "The version, iOS and device model. Never anything about you.", bundle: .module,
            comment: "Send feedback: under the Include app details switch while it's on")
    }

    static var previewHeader: String {
        String(localized: "What’s sent", bundle: .module, comment: "Send feedback: above the preview")
    }

    static var previewEmpty: String {
        String(
            localized: "Your note shows here, exactly as it will be sent.", bundle: .module,
            comment: "Send feedback: the preview before she has written anything")
    }

    static var neverSent: String {
        String(
            localized: "Never your closet, photos, measurements, looks or name.", bundle: .module,
            comment: "Send feedback: under the preview")
    }

    static var send: String {
        String(localized: "Send privately", bundle: .module, comment: "Send feedback: the button")
    }

    static var howItGoes: String {
        String(
            localized:
                "The app doesn’t send anything itself. Send opens the share sheet, and you choose where the note goes, like Messages or Mail.",
            bundle: .module, comment: "Send feedback: under the button, in this test build")
    }

    static var thanksTitle: String {
        String(localized: "Thank you", bundle: .module, comment: "Send feedback: after sending")
    }

    static var thanksMessage: String {
        String(
            localized: "Your note went where you sent it. This is what it said.", bundle: .module,
            comment: "Send feedback: after sending")
    }

    static var done: String {
        String(localized: "Done", bundle: .module, comment: "Button: closes Send feedback after sending")
    }

    static var writeAnother: String {
        String(localized: "Write another", bundle: .module, comment: "Button: starts a new note")
    }
}

nonisolated extension FeedbackKind {
    /// "Something’s wrong", "An idea", "Other" (`feedback.html`).
    nonisolated var title: String {
        switch self {
        case .somethingWrong:
            String(localized: "Something’s wrong", bundle: .module, comment: "Send feedback: kind chip")
        case .idea: String(localized: "An idea", bundle: .module, comment: "Send feedback: kind chip")
        case .other: String(localized: "Other", bundle: .module, comment: "Send feedback: kind chip")
        }
    }
}
