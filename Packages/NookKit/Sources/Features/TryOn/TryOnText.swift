import Foundation
import Models

/// The words for Try it on, the Pictures tab and picture detail (Phase 12b).
enum TryOnText {
    static var tryOn: String {
        String(localized: "Try it on", bundle: .module, comment: "Results button (RD-06)")
    }

    static var pictureTitle: String {
        String(localized: "Try-on picture", bundle: .module, comment: "Title of one try-on picture")
    }

    /// What VoiceOver says for a picture: "Simulated try-on picture of Interview navy and pink:
    /// Navy cardigan, Cute pink shirt, … No person is shown."
    static func spokenPicture(of content: LookBundleContent, lookName: String, locale: Locale) -> String {
        let pieces = content.pieces.map(\.name).formatted(.list(type: .and, width: .narrow).locale(locale))
        return String(
            localized: "Simulated try-on picture of \(lookName): \(pieces). No person is shown.", bundle: .module,
            comment: "Spoken for a simulated try-on picture: the look's name, then its pieces")
    }

    /// "Made today", "Made yesterday", "Made 28 Aug".
    static func made(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        switch WearRules.days(from: date, to: now, calendar: calendar) {
        case ..<1:
            return String(localized: "Made today", bundle: .module, comment: "When a try-on picture was made")
        case 1:
            return String(localized: "Made yesterday", bundle: .module, comment: "When a try-on picture was made")
        default:
            let formatted = ShortDateText.format(date, now: now, calendar: calendar, locale: locale)
            return String(
                localized: "Made \(formatted)", bundle: .module,
                comment: "When a try-on picture was made, a date such as 28 Aug")
        }
    }

    /// The short date under a picture in the grid: "Today", "Yesterday", "28 Aug".
    static func shortDate(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        switch WearRules.days(from: date, to: now, calendar: calendar) {
        case ..<1: String(localized: "Today", bundle: .module, comment: "A picture made today")
        case 1: String(localized: "Yesterday", bundle: .module, comment: "A picture made yesterday")
        default: ShortDateText.format(date, now: now, calendar: calendar, locale: locale)
        }
    }

    /// "3 pictures", "1 picture".
    static func pictures(_ count: Int) -> String {
        String(localized: "\(count) pictures", bundle: .module, comment: "How many try-on pictures")
    }

    // MARK: The link between a picture and its look

    static var fromTheLook: String {
        String(localized: "From the look", bundle: .module, comment: "Over the name of the look a picture came from")
    }

    static var seeTheLook: String {
        String(localized: "See the look", bundle: .module, comment: "Button: opens the look a picture came from")
    }

    static func seeTheLook(_ name: String) -> String {
        String(
            localized: "See the look: \(name)", bundle: .module,
            comment: "Spoken label of the link from a picture to its look")
    }

    /// Under the look's name when the look changed since the picture (a swap).
    static var earlierVersion: String {
        String(
            localized: "The look has changed since. This picture shows an earlier version.", bundle: .module,
            comment: "Picture detail: its look changed after the picture was made")
    }

    static var earlierVersionShort: String {
        String(localized: "Earlier version", bundle: .module, comment: "A picture of an earlier version of its look")
    }

    /// When the look left Saved Looks. The picture stays (PRD §7.5).
    static var lookNotSaved: String {
        String(
            localized: "Its look isn’t in Saved Looks any more. The picture stays until you delete it.",
            bundle: .module, comment: "Picture detail: its look was deleted")
    }

    static var lookNotSavedShort: String {
        String(localized: "Look deleted", bundle: .module, comment: "Under a picture whose look was deleted")
    }

    /// The note at the end of picture detail.
    static var aboutSimulated: String {
        String(
            localized:
                "This picture is simulated: it shows the look’s pieces, not you. In a later version, Try it on will show you wearing the look. Pictures show the style, not the exact fit.",
            bundle: .module, comment: "Picture detail: what a simulated picture is")
    }

    // MARK: Delete

    static var delete: String {
        String(localized: "Delete picture", bundle: .module, comment: "Button on picture detail")
    }

    static var deleteHint: String {
        String(
            localized: "Removes this picture. The look stays saved. You can undo it.", bundle: .module,
            comment: "Hint on Delete picture")
    }

    static var deleted: String {
        String(localized: "Picture deleted", bundle: .module, comment: "Toast after Delete picture")
    }

    // MARK: Pictures tab

    static var searchPrompt: String {
        String(localized: "Search your pictures", bundle: .module, comment: "Pictures tab search field prompt")
    }

    static var emptyTitle: String {
        String(localized: "No try-on pictures yet", bundle: .module, comment: "Saved Looks Pictures tab, empty")
    }

    static var emptyMessage: String {
        String(
            localized: "A picture shows one of your looks. Pictures are made one look at a time, only when you ask.",
            bundle: .module, comment: "Saved Looks Pictures tab, empty")
    }

    /// How to make a picture, step by step.
    static var emptySteps: [String] {
        [
            String(
                localized: "Save a look, from Style Me or with Make your own.", bundle: .module,
                comment: "Pictures tab empty state: step 1"),
            String(
                localized: "Open the look and tap Try it on. Pictures in this test build are simulated.",
                bundle: .module, comment: "Pictures tab empty state: step 2"),
        ]
    }

    static var seeYourLooks: String {
        String(localized: "See your looks", bundle: .module, comment: "Button: switches to the Looks tab")
    }

    static var noMatchesTitle: String {
        String(localized: "No pictures match", bundle: .module, comment: "Pictures tab: nothing matches")
    }

    static var loading: String {
        String(localized: "Opening your pictures", bundle: .module, comment: "Pictures tab loading")
    }

    static var failedTitle: String {
        String(localized: "Your pictures didn’t load", bundle: .module, comment: "Pictures tab error title")
    }

    static var openHint: String {
        String(localized: "Opens the picture.", bundle: .module, comment: "Hint on a try-on picture")
    }

    /// In a wide window, where the picture shows beside the grid (Phase 15b).
    static var showBesideHint: String {
        String(
            localized: "Shows the picture beside your pictures.", bundle: .module,
            comment: "Hint on a try-on picture on iPad, where its detail opens beside the grid")
    }

    // MARK: Look detail

    static var picturesHeading: String {
        String(localized: "Pictures", bundle: .module, comment: "Look detail: heading over the look's pictures")
    }
}
