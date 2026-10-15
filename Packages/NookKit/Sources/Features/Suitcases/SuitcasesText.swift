import Foundation
import Models

/// The words on Suitcases and a suitcase's page (Phase 13), from stored facts with a given
/// clock, calendar and locale, so tests can pin them.
nonisolated enum SuitcasesText {
    static var title: String {
        String(localized: "Suitcases", bundle: .module, comment: "Screen title")
    }

    static var allTitle: String {
        String(localized: "All suitcases", bundle: .module, comment: "Screen title: every suitcase (RD-09)")
    }

    static var mainCloset: String {
        String(localized: "Main closet", bundle: .module, comment: "Source plate: the whole closet")
    }

    static var addSuitcase: String {
        String(localized: "Add a suitcase", bundle: .module, comment: "Button: makes a new suitcase (LR-17)")
    }

    static var favourites: String {
        String(localized: "Favourites", bundle: .module, comment: "Suitcases: heading over the three favourites")
    }

    static var favouritesNote: String {
        String(
            localized: "Your three most recently used.", bundle: .module,
            comment: "Suitcases: under Favourites, how they're chosen (RD-09: no star)")
    }

    static var otherSuitcases: String {
        String(localized: "Other suitcases", bundle: .module, comment: "All suitcases: heading after the favourites")
    }

    static var archived: String {
        String(localized: "Archived", bundle: .module, comment: "All suitcases: heading and filter for archived ones")
    }

    static var sourceNote: String {
        String(
            localized: "Style Me picks only from the suitcase you choose. Main closet uses everything.",
            bundle: .module, comment: "Suitcases: what choosing a source does")
    }

    static var styleMeSource: String {
        String(localized: "Style Me source", bundle: .module, comment: "Suitcases: the chosen source's mark")
    }

    /// "See all 5": the link under the favourites when there are more than three (RD-09).
    static func seeAll(_ count: Int) -> String {
        String(
            localized: "See all \(count)", bundle: .module,
            comment: "Suitcases: opens every suitcase, with how many there are")
    }

    /// "6 suitcases" under All suitcases' title.
    static func suitcaseCount(_ count: Int) -> String {
        String(
            localized: "\(count) suitcases", bundle: .module, comment: "Closet tile: how many suitcases she has")
    }

    /// "5 pieces", "1 piece" or "Empty".
    static func pieces(_ count: Int) -> String {
        if count == 0 {
            return String(localized: "Empty", bundle: .module, comment: "Source plate: the source has no pieces")
        }
        return String(
            localized: "\(count) pieces", bundle: .module, comment: "Source plate: how many pieces the source has")
    }

    /// The main closet's line: "All 17 pieces", or "1 piece" and "Empty" when there are fewer.
    static func closetPieces(_ count: Int) -> String {
        guard count > 1 else { return pieces(count) }
        return String(
            localized: "All \(count) pieces", bundle: .module,
            comment: "Suitcases: the main closet's row, every piece in her closet (always 2 or more)")
    }

    /// "Used today", "Used 3 days ago", "Used 2 weeks ago", "Last used Jul 3", "Not used yet".
    static func lastUsed(_ date: Date?, now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let date else {
            return String(
                localized: "Not used yet", bundle: .module, comment: "Suitcases: a suitcase never used for Style Me")
        }
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        switch days {
        case ..<1:
            return String(localized: "Used today", bundle: .module, comment: "Suitcases: when it was last used")
        case 1:
            return String(localized: "Used yesterday", bundle: .module, comment: "Suitcases: when it was last used")
        case 2..<7:
            return String(
                localized: "Used \(days) days ago", bundle: .module,
                comment: "Suitcases: when it was last used, 2 to 6 days ago")
        case 7..<14:
            return String(localized: "Used last week", bundle: .module, comment: "Suitcases: when it was last used")
        case 14..<28:
            let weeks = days / 7
            return String(
                localized: "Used \(weeks) weeks ago", bundle: .module,
                comment: "Suitcases: when it was last used, 2 or 3 weeks ago")
        default:
            let formatted = ShortDateText.format(date, now: now, calendar: calendar, locale: locale)
            return String(
                localized: "Last used \(formatted)", bundle: .module,
                comment: "Suitcases: when it was last used, a date such as Jul 3")
        }
    }

    /// A row's second line: "5 pieces · Used today", or "Style Me source · 5 pieces" for the
    /// chosen one.
    static func rowDetail(pieceCount: Int, lastUsed: String, isChosen: Bool) -> String {
        isChosen ? "\(styleMeSource) · \(pieces(pieceCount))" : "\(pieces(pieceCount)) · \(lastUsed)"
    }

    /// What a picture is called, for VoiceOver on the picture choices.
    static func iconName(_ icon: SuitcaseIcon) -> String {
        switch icon {
        case .rolling: String(localized: "Rolling case", bundle: .module, comment: "A suitcase picture")
        case .weekender: String(localized: "Weekender", bundle: .module, comment: "A suitcase picture")
        case .duffel: String(localized: "Duffel bag", bundle: .module, comment: "A suitcase picture")
        case .backpack: String(localized: "Backpack", bundle: .module, comment: "A suitcase picture")
        case .tote: String(localized: "Tote bag", bundle: .module, comment: "A suitcase picture")
        }
    }

    /// Why a suitcase name can't be saved, in words.
    static func nameLine(for problem: NameProblem) -> String {
        switch problem {
        case .empty:
            String(localized: "Give the suitcase a name.", bundle: .module, comment: "Suitcase name: empty")
        case .tooLong(let maximum):
            String(
                localized: "Use \(maximum) characters or fewer.", bundle: .module,
                comment: "Make your own look: the name is too long")
        case .controlCharacters:
            String(
                localized: "Use one line of letters, numbers and spaces.", bundle: .module,
                comment: "Make your own look: the name has line breaks or tabs")
        case .duplicate:
            String(
                localized: "You already have a suitcase with this name.", bundle: .module,
                comment: "Suitcase name: another suitcase has it")
        }
    }

    // MARK: Toasts

    static func nowUsing(_ name: String) -> String {
        String(
            localized: "Style Me now uses \(name).", bundle: .module,
            comment: "Toast after choosing a source, with its name")
    }

    static func isEmpty(_ name: String) -> String {
        String(
            localized: "\(name) is empty. Pack something first.", bundle: .module,
            comment: "Toast after choosing an empty suitcase as the source; the source stays as it was")
    }

    static var packIt: String {
        String(localized: "Pack it", bundle: .module, comment: "Toast action: opens the empty suitcase to pack it")
    }

    static var styleMe: String {
        String(localized: "Style me", bundle: .module, comment: "Toast action: opens Style Me")
    }

    static var undo: String {
        String(localized: "Undo", bundle: .module, comment: "Toast action")
    }

    static var failed: String {
        String(
            localized: "That didn’t save. Nothing changed.", bundle: .module,
            comment: "Toast when a change to a piece couldn't be saved")
    }
}
