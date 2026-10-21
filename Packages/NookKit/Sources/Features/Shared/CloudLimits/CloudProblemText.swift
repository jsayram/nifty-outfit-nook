import Foundation
import Models
import SwiftUI

/// The plain words for a failed cloud call, and the VoiceOver announcement of them (Phase 26).
/// Every wording follows `CloudLimitText` (24b): say what happened and when to try again, never
/// blame her, and say her closet still works. A cancelled call has no words: leaving a screen or
/// tapping Cancel is not a failure.
nonisolated public enum CloudProblemText {
    /// The words for an account or network problem, or nil for a cancellation.
    public static func message(for problem: AccountProblem) -> String? {
        switch problem {
        case .cancelled:
            nil
        case .offline:
            String(
                localized: "You're offline. Your closet still works on this iPhone.", bundle: .module,
                comment: "Cloud action: no connection")
        case .timedOut:
            String(
                localized: "That's taking longer than it should. Try again in a moment.", bundle: .module,
                comment: "Cloud action: the server didn't answer in time")
        case .rateLimited(let seconds):
            String(
                localized: "You've asked a lot in the last minute. Try again in \(CloudLimitText.waitText(seconds)).",
                bundle: .module,
                comment: "Cloud limit: too many requests in a short time. The argument is a wait, like '12 seconds'.")
        case .unavailable(let seconds?):
            String(
                localized: "This isn't available right now. Try again in \(CloudLimitText.waitText(seconds)).",
                bundle: .module,
                comment: "Cloud action: the server is busy or paused. The argument is a wait, like '2 minutes'.")
        case .unavailable(nil):
            String(
                localized: "This isn't available right now. Try again later.", bundle: .module,
                comment: "Cloud action: the server is busy or paused, with no time given")
        case .forbidden:
            String(
                localized: "This account can't do that.", bundle: .module, comment: "Cloud action: not allowed")
        case .signedOut:
            String(
                localized: "Sign in to use cloud styling.", bundle: .module, comment: "Cloud action: signed out")
        case .serverError:
            String(
                localized: "Something went wrong on our side. Try again later.", bundle: .module,
                comment: "Cloud action: the server failed, even after retrying")
        case .updateRequired:
            String(
                localized: "Update the app to keep using cloud styling.", bundle: .module,
                comment: "Cloud action: this app version is too old for the server")
        case .invalidResponse, .rejected:
            String(
                localized: "Something went wrong. Try again later.", bundle: .module,
                comment: "Cloud action: any other failure")
        }
    }

    /// What still works while offline, under "You're offline."
    public static var offlineDetail: String {
        String(
            localized: "Your closet still works on this iPhone.", bundle: .module,
            comment: "Offline banner where cloud styling is needed: what still works")
    }

    /// VoiceOver reads a failure aloud as it appears, so it isn't missed when focus is elsewhere.
    @MainActor public static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
