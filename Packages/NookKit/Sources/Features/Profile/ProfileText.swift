import Foundation
import Models

/// The words on Profile and its sheets (Phase 14a, `settings.html`).
nonisolated enum ProfileText {
    static var title: String {
        String(localized: "Profile", bundle: .module, comment: "Screen title")
    }

    static var failed: String {
        String(
            localized: "Couldn’t save that. Try again.", bundle: .module,
            comment: "Profile toast: a setting didn't save")
    }

    // MARK: Rows

    static var nameRow: String {
        String(localized: "Name on your sign", bundle: .module, comment: "Profile row (RD-03)")
    }

    static var nameRowDetail: String {
        String(localized: "Shown in your room", bundle: .module, comment: "Under the Name on your sign row")
    }

    static var fitRow: String {
        String(localized: "Fit and measurements", bundle: .module, comment: "Profile row and screen title")
    }

    static var fitRowDetail: String {
        String(
            localized: "Optional · stays on this iPhone", bundle: .module, comment: "Under the Fit and measurements row"
        )
    }

    static var photoRow: String {
        String(localized: "Your try-on photo", bundle: .module, comment: "Profile row and sheet title (RD-06)")
    }

    static var photoRowDetail: String {
        String(
            localized: "For try-on pictures later", bundle: .module, comment: "Under the Your try-on photo row")
    }

    static var photoAdded: String {
        String(localized: "Added", bundle: .module, comment: "Your try-on photo row value: a photo is set")
    }

    static var photoNotAdded: String {
        String(localized: "Not added", bundle: .module, comment: "Your try-on photo row value: no photo")
    }

    static var styleMeSection: String {
        String(localized: "Style Me", bundle: .module, comment: "Profile section header")
    }

    static var preferencesRow: String {
        String(localized: "Preferences", bundle: .module, comment: "Profile row: Style Me's usual Preferences (LR-03)")
    }

    static var preferencesRowDetail: String {
        String(
            localized: "What Style Me starts with", bundle: .module, comment: "Under the Preferences row in Profile")
    }

    static var repeatRow: String {
        String(
            localized: "Avoid repeating outfits for", bundle: .module, comment: "Profile row (LR-10), value after it")
    }

    static var laundryRow: String {
        String(localized: "Track laundry", bundle: .module, comment: "Profile row (RD-11)")
    }

    static var on: String {
        String(localized: "On", bundle: .module, comment: "A switch's value on a row")
    }

    static var off: String {
        String(localized: "Off", bundle: .module, comment: "A switch's value on a row")
    }

    static var helpSection: String {
        String(localized: "Help and privacy", bundle: .module, comment: "Profile section header")
    }

    static var accessibilityRow: String {
        String(localized: "Accessibility", bundle: .module, comment: "Profile row and screen title")
    }

    static var toursRow: String {
        String(localized: "App tours", bundle: .module, comment: "Profile row and screen title")
    }

    static var toursRowDetail: String {
        String(localized: "Replay the tips for any screen", bundle: .module, comment: "Under the App tours row")
    }

    static var helpRow: String {
        String(localized: "Help", bundle: .module, comment: "Screen title")
    }

    static var feedbackRow: String {
        String(localized: "Send feedback", bundle: .module, comment: "Screen title")
    }

    static var privacyRow: String {
        String(localized: "Privacy and terms", bundle: .module, comment: "Screen title")
    }

    static var deleteDataRow: String {
        String(localized: "Delete my data", bundle: .module, comment: "Profile row and screen title")
    }

    static var laterMessage: String {
        String(
            localized: "This part of Profile comes in the next update.", bundle: .module,
            comment: "Profile: a row whose screen isn't built yet")
    }

    static var laundryLaterMessage: String {
        String(
            localized:
                "The switch comes in the next update. For now, turn tracking on from the hamper on Home or from Laundry.",
            bundle: .module, comment: "Profile: the Track laundry row's stand-in")
    }

    // MARK: Name on your sign

    static var nameSheetLine: String {
        String(
            localized: "The sign in your room shows this name. It stays on this iPhone.", bundle: .module,
            comment: "Name on your sign sheet, under the title")
    }

    static var nameField: String {
        String(localized: "Name", bundle: .module, comment: "Name on your sign: the field's label")
    }

    static var namePrompt: String {
        String(localized: "Your first name", bundle: .module, comment: "Name on your sign: the empty field's prompt")
    }

    static var nameEmptyNote: String {
        String(
            localized: "Leave it empty and the sign says “Hello”.", bundle: .module,
            comment: "Name on your sign: what an empty name does (RD-03.2)")
    }

    static var signPreview: String {
        String(localized: "Your sign", bundle: .module, comment: "Name on your sign: above the live preview")
    }

    static var save: String {
        String(localized: "Save", bundle: .module, comment: "Button: saves")
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Button: closes without changing anything")
    }

    static func nameProblem(_ problem: NameProblem) -> String {
        switch problem {
        case .tooLong(let maximum):
            String(
                localized: "Use \(maximum) characters or fewer.", bundle: .module,
                comment: "Make your own look: the name is too long")
        case .empty, .controlCharacters, .duplicate:
            String(
                localized: "Use one line of letters, numbers and spaces.", bundle: .module,
                comment: "Make your own look: the name has line breaks or tabs")
        }
    }

    /// The toast after saving: "Your sign now says Lily."
    static func signSays(_ shown: String) -> String {
        String(
            localized: "Your sign now says \(shown).", bundle: .module,
            comment: "Toast after changing the name on the sign, with what it shows")
    }

    /// The sign as one VoiceOver element on Profile.
    static func spokenSign(_ stored: String) -> String {
        SignName.isFallback(stored)
            ? String(
                localized: "Name on your sign, no name yet", bundle: .module,
                comment: "VoiceOver: Profile's sign when no name is set")
            : String(
                localized: "Name on your sign: \(stored)", bundle: .module,
                comment: "VoiceOver: Profile's sign, with the name")
    }

    static var signHint: String {
        String(localized: "Changes the name.", bundle: .module, comment: "VoiceOver hint on Profile's sign")
    }

    // MARK: Preferences and repeats

    static var preferencesNote: String {
        String(
            localized: "Style Me starts with this each time. You can change it there for one request.",
            bundle: .module, comment: "Profile's Preferences sheet note (LR-03)")
    }

    static var repeatNote: String {
        String(
            localized: "Single favourite pieces can still come back. Only whole outfits are spaced out.",
            bundle: .module, comment: "Profile's repeat sheet note (LR-10)")
    }
}

extension RepeatWindow {
    /// "1 week", "2 weeks", "I don't mind" (LR-10).
    nonisolated var title: String {
        switch self {
        case .oneWeek: String(localized: "1 week", bundle: .module, comment: "Repeat setting value (LR-10)")
        case .twoWeeks: String(localized: "2 weeks", bundle: .module, comment: "Repeat setting value (LR-10)")
        case .noLimit: String(localized: "I don’t mind", bundle: .module, comment: "Repeat setting value (LR-10)")
        }
    }

    /// What it does, in the sheet.
    nonisolated var detail: String {
        switch self {
        case .oneWeek:
            String(
                localized: "Style Me won’t suggest an outfit you wore in the last week.", bundle: .module,
                comment: "Repeat setting: 1 week")
        case .twoWeeks:
            String(
                localized: "Style Me won’t suggest an outfit you wore in the last 2 weeks.", bundle: .module,
                comment: "Repeat setting: 2 weeks")
        case .noLimit:
            String(
                localized: "Outfits can come back any time.", bundle: .module, comment: "Repeat setting: I don't mind")
        }
    }
}
