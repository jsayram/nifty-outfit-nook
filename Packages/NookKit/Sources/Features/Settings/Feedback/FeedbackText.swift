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
        // The support queue's extras (24d). None of them is ever in a note that goes to the share sheet.
        var extras: [String] = []
        if let address = note.replyAddress { extras.append(FeedbackText.replyLine(address)) }
        if let counts = note.closetCounts { extras.append(FeedbackText.closetLine(counts)) }
        if let health = note.deviceHealth { extras.append(contentsOf: FeedbackText.healthLines(health)) }
        if let screenshot = note.screenshot { extras.append(FeedbackText.screenshotLine(screenshot)) }
        if !extras.isEmpty {
            lines.append("")
            lines.append(contentsOf: extras)
        }
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

    // MARK: The support queue (24d)

    static func replyLine(_ address: String) -> String {
        String(
            localized: "Reply address: \(address)", bundle: .module,
            comment: "Send feedback: a line of what's sent, the address she gave to be answered at")
    }

    static func closetLine(_ counts: FeedbackClosetCounts) -> String {
        String(
            localized: "Closet size: \(counts.pieces) pieces, \(counts.looks) looks, \(counts.suitcases) suitcases",
            bundle: .module,
            comment: "Send feedback: a line of what's sent, three numbers and no names")
    }

    static func screenshotLine(_ screenshot: FeedbackScreenshot) -> String {
        let size = screenshot.data.count.formatted(.byteCount(style: .file))
        return String(
            localized: "Screenshot: 1 picture, \(size)", bundle: .module,
            comment: "Send feedback: a line of what's sent, with the picture's size like 143 KB")
    }

    static var replyLabel: String {
        String(localized: "Reply address", bundle: .module, comment: "Send feedback: the field's name")
    }

    static var replyPrompt: String {
        String(localized: "you@example.com", bundle: .module, comment: "Send feedback: the empty reply field")
    }

    static var replyHint: String {
        String(
            localized: "We’ll use it only to answer this note. Without one, we can’t answer you.",
            bundle: .module, comment: "Send feedback: under the reply address field")
    }

    static var replyProblem: String {
        String(
            localized: "That doesn’t look like an email address.", bundle: .module,
            comment: "Send feedback: the reply address isn't an address")
    }

    static var screenshotHeader: String {
        String(localized: "Screenshot", bundle: .module, comment: "Send feedback: above the screenshot row")
    }

    static var addScreenshot: String {
        String(localized: "Add a screenshot", bundle: .module, comment: "Send feedback: the row that opens the picker")
    }

    static var chooseAnother: String {
        String(localized: "Choose another", bundle: .module, comment: "Send feedback: replaces the screenshot")
    }

    static var removeScreenshot: String {
        String(localized: "Remove", bundle: .module, comment: "Send feedback: removes the screenshot")
    }

    static var screenshotHint: String {
        String(
            localized:
                "Choose it yourself, and check it first: a screenshot can show your closet. Its location and other photo details are removed before it leaves your phone.",
            bundle: .module, comment: "Send feedback: under the screenshot row")
    }

    static var screenshotPreparing: String {
        String(
            localized: "Getting your screenshot ready…", bundle: .module,
            comment: "Send feedback: while the picture is shrunk and cleaned")
    }

    static func screenshotProblem(_ problem: FeedbackScreenshotProblem) -> String {
        switch problem {
        case .unreadable:
            String(
                localized: "That picture couldn’t be read. Try another.", bundle: .module,
                comment: "Send feedback: the screenshot isn't a picture the phone can open")
        case .tooLarge:
            String(
                localized: "That picture is too large to send. Try another.", bundle: .module,
                comment: "Send feedback: the screenshot is too big even after shrinking")
        }
    }

    static var screenshotLabel: String {
        String(
            localized: "Your screenshot", bundle: .module, comment: "Send feedback: the attached picture's description")
    }

    static var closetRow: String {
        String(localized: "Include my closet’s size", bundle: .module, comment: "Send feedback: the switch")
    }

    static var closetRowOff: String {
        String(
            localized: "Off unless you turn it on.", bundle: .module, comment: "Send feedback: under the closet switch")
    }

    static var closetRowOn: String {
        String(
            localized: "How many pieces, looks and suitcases. Never their names or photos.", bundle: .module,
            comment: "Send feedback: under the closet switch while it's on")
    }

    // MARK: Crash and speed details (31)

    /// The lines "Share crash and speed details" adds, exactly as they're sent: every number and
    /// name in the summary appears in one of them.
    static func healthLines(_ health: DeviceHealthSummary) -> [String] {
        var lines = [
            String(
                localized: "Crash and speed details, last \(String(health.windowDays)) days:", bundle: .module,
                comment: "Send feedback: heading of the phone's crash and speed counts, with a number of days"),
            String(
                localized:
                    "Crashes: \(String(health.crashes)). Hangs: \(String(health.hangs)). Heavy processor use: \(String(health.cpuExceptions)). Heavy disk writing: \(String(health.diskWriteExceptions)).",
                bundle: .module, comment: "Send feedback: four counts from the phone's reports"),
            String(
                localized:
                    "Ended by the system: \(String(health.memoryExits)) for memory, \(String(health.watchdogExits)) for being too slow.",
                bundle: .module, comment: "Send feedback: two counts from the phone's reports"),
        ]
        var timings: [String] = []
        if let hang = health.longestHangMs {
            timings.append(
                String(
                    localized: "Longest hang: \(String(hang)) ms.", bundle: .module,
                    comment: "Send feedback: the longest time the app stopped answering, in milliseconds"))
        }
        if let launch = health.launchMedianMs {
            timings.append(
                String(
                    localized: "Typical start-up: \(String(launch)) ms.", bundle: .module,
                    comment: "Send feedback: the typical time to open the app, in milliseconds"))
        }
        if let memory = health.peakMemoryMB {
            timings.append(
                String(
                    localized: "Most memory used: \(String(memory)) MB.", bundle: .module,
                    comment: "Send feedback: the most memory the app used, in megabytes"))
        }
        if !timings.isEmpty { lines.append(timings.joined(separator: " ")) }
        for kind in health.crashKinds {
            lines.append(
                String(
                    localized:
                        "Crash type: \(kind.exception.rawValue), \(kind.signal.rawValue), \(String(kind.count)) times.",
                    bundle: .module, comment: "Send feedback: one kind of crash, with fixed names and a count"))
        }
        return lines
    }

    static var healthRow: String {
        String(
            localized: "Share crash and speed details", bundle: .module,
            comment: "Send feedback: the switch for the phone's crash and speed counts")
    }

    static var healthRowOff: String {
        String(
            localized: "Off unless you turn it on. Helps to find a problem that crashes or slows the app.",
            bundle: .module, comment: "Send feedback: under the crash and speed switch")
    }

    static var healthRowOn: String {
        String(
            localized: "Counts and timings from your phone’s own reports. No screens, pieces, names or places.",
            bundle: .module, comment: "Send feedback: under the crash and speed switch while it's on")
    }

    static var queueNote: String {
        String(
            localized: "This note goes to the app’s private support inbox. Only what you see here is sent.",
            bundle: .module, comment: "Send feedback: under the preview when it goes to the support inbox")
    }

    static var queueHowItGoes: String {
        String(
            localized:
                "Send goes straight to the support inbox. If it can’t go now, your note stays here and you can tap Send again.",
            bundle: .module, comment: "Send feedback: under the button when it goes to the support inbox")
    }

    static var sending: String {
        String(localized: "Sending…", bundle: .module, comment: "Send feedback: the button while it sends")
    }

    static var supportPageRow: String {
        String(localized: "Support page", bundle: .module, comment: "Send feedback: a link row")
    }

    static var supportPageDetail: String {
        String(
            localized: "Other ways to reach us, on the website.", bundle: .module,
            comment: "Send feedback: under the support page row")
    }

    static var sentAnnouncement: String {
        String(
            localized: "Your note was sent.", bundle: .module, comment: "Spoken after a note reached the support inbox")
    }

    static var thanksQueueMessage: String {
        String(
            localized: "Your note reached the support inbox. This is what it said.", bundle: .module,
            comment: "Send feedback: after sending to the support inbox")
    }

    static func referenceLine(_ reference: String) -> String {
        String(
            localized: "Reference: \(reference)", bundle: .module,
            comment: "Send feedback: after sending, the note's reference to quote if she writes again")
    }

    static var noReplyAddressNote: String {
        String(
            localized: "You didn’t give a reply address, so we can’t answer this note.", bundle: .module,
            comment: "Send feedback: after sending without a reply address")
    }

    static func sendProblem(_ problem: FeedbackSendProblem, hasScreenshot: Bool) -> String {
        switch problem {
        case .offline:
            String(
                localized: "No connection. Your note is saved here. Tap Send again when you’re back online.",
                bundle: .module, comment: "Send feedback: no connection")
        case .timedOut:
            String(
                localized: "That took too long. Your note is saved here. Tap Send again to try once more.",
                bundle: .module, comment: "Send feedback: the server didn't answer in time")
        case .signedOut:
            String(
                localized: "You’re not signed in any more. Your note is saved here.", bundle: .module,
                comment: "Send feedback: the session ended")
        case .rateLimited(let seconds):
            String(
                localized: "You’ve sent a lot of notes. Try again in \(CloudLimitText.waitText(seconds)).",
                bundle: .module, comment: "Send feedback: too many notes; the argument is a wait like '5 minutes'")
        case .unavailable:
            String(
                localized:
                    "Sending notes is paused for now. Your note is saved here. Try again later, or use the support page.",
                bundle: .module, comment: "Send feedback: the support inbox is paused or busy")
        case .screenshotRefused where hasScreenshot:
            String(
                localized: "The screenshot couldn’t be used. Remove it or choose another, then send again.",
                bundle: .module, comment: "Send feedback: the server refused the picture")
        case .updateRequired:
            String(
                localized: "Update the app to send notes.", bundle: .module,
                comment: "Send feedback: this version is too old for the server")
        case .screenshotRefused, .serverError, .rejected:
            String(
                localized: "Something went wrong on our side. Your note is saved here. Try again later.",
                bundle: .module, comment: "Send feedback: the server failed")
        }
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
        case .badReplyAddress: replyProblem
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
