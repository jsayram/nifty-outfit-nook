import Foundation
import Models

/// The words garment detail shows for one piece, worked out from stored facts with a fixed
/// clock, calendar and locale, so tests can check every line.
///
/// Sources: LR-10 (Last worn and the recent-wear note), LR-11 (its suitcases), RD-11 (laundry
/// only while tracking is on), LR-16 (the Delete it deadline) and PRD §7.4.
struct GarmentDetailText {
    let garment: Garment
    let tracksLaundry: Bool
    let repeatWindow: RepeatWindow
    let now: Date
    let calendar: Calendar
    let locale: Locale

    // MARK: Wear (LR-10)

    /// "Last worn 5 days ago", "Last worn Oct 7", or "Not marked as worn yet". Wear is only what
    /// she recorded with Wear today, so an empty record doesn't claim she never wore it.
    var lastWorn: String {
        guard let lastWorn = garment.lastWorn else {
            return String(
                localized: "Not marked as worn yet", bundle: .module,
                comment: "Garment detail: she hasn't used Wear today with this piece")
        }
        return LastWornText.describe(lastWorn, now: now, calendar: calendar, locale: locale)
    }

    /// True when she wore it inside her repeat window and it's a main piece (a top, bottom or
    /// dress), the pieces whose combinations Style Me avoids repeating (LR-10). Shoes, layers,
    /// bags and accessories can repeat freely, and "I don't mind" makes nothing recent.
    var isWornRecently: Bool {
        guard let lastWorn = garment.lastWorn, WearRules.mainCategories.contains(garment.category) else {
            return false
        }
        return WearRules.isRecent(lastWorn, window: repeatWindow, now: now, calendar: calendar)
    }

    /// The quiet note under Last worn while the repeat window applies, naming her setting.
    var recentWearNote: String? {
        guard isWornRecently else { return nil }
        switch repeatWindow {
        case .oneWeek:
            return String(
                localized: "Style Me won’t repeat an outfit you wore it in during the last week.", bundle: .module,
                comment: "Garment detail: recent-wear note with the repeat setting at 1 week (LR-10)")
        case .twoWeeks:
            return String(
                localized: "Style Me won’t repeat an outfit you wore it in during the last 2 weeks.", bundle: .module,
                comment: "Garment detail: recent-wear note with the repeat setting at 2 weeks (LR-10)")
        case .noLimit:
            return nil
        }
    }

    // MARK: Facts

    /// The kind of piece, as the Closet chip that finds it says it: "Bottoms".
    var kind: String { garment.category.chipTitle }

    /// Its type, under the kind: "Cardigan". `nil` when she didn't pick one.
    var subKind: String? { garment.subKind?.title }

    /// Her other names for it, in her order: "Date-night top, The bow one". `nil` when there are
    /// none (Phase 21c).
    var otherNames: String? {
        garment.otherNames.isEmpty ? nil : garment.otherNames.joined(separator: ", ")
    }

    /// "Navy", or "Blue, White". `nil` when no colour is recorded.
    var colors: String? {
        garment.colors.isEmpty ? nil : garment.colors.map(\.title).joined(separator: ", ")
    }

    /// Her words for the shade, such as "Muted olive".
    var colorNote: String? { garment.colorNote.flatMap(Self.nonEmpty) }

    var fit: String? { garment.fit?.title }

    /// "All year", or "Spring, Fall". `nil` when unknown.
    var seasons: String? {
        let seasons = Season.allCases.filter(garment.seasons.contains)
        if seasons.isEmpty { return nil }
        if seasons.count == Season.allCases.count {
            return String(localized: "All year", bundle: .module, comment: "Garment detail: worn in every season")
        }
        return seasons.map(\.title).joined(separator: ", ")
    }

    /// "Office, Date night, Event", in a fixed order. `nil` when unknown.
    var occasions: String? {
        let occasions = Occasion.allCases.filter(garment.occasions.contains)
        return occasions.isEmpty ? nil : occasions.map(\.title).joined(separator: ", ")
    }

    var brand: String? { garment.brand.flatMap(Self.nonEmpty) }
    var size: String? { garment.sizeLabel.flatMap(Self.nonEmpty) }
    /// Her notes. Sensitive tier: shown on her own screen, never logged.
    var notes: String? { Self.nonEmpty(garment.notes) }

    /// True when the "In the wash" mark shows on the picture: dirty while tracking is on (RD-11).
    var isInTheWash: Bool { tracksLaundry && garment.laundry == .dirty }

    /// The Status fact: whether she can wear it now. Laundry shows only while tracking is on;
    /// otherwise a piece with nothing in the way is "Available", as in `garment.html`.
    var status: String {
        var parts: [String] = []
        switch garment.ownership {
        case .owned, .purchased(.arrived): break
        case .purchased:
            parts.append(
                String(localized: "Bought, not here yet", bundle: .module, comment: "Garment status: not arrived"))
        case .wishlisted:
            parts.append(String(localized: "On your wishlist", bundle: .module, comment: "Garment status"))
        case .noLongerOwned:
            parts.append(String(localized: "No longer in your closet", bundle: .module, comment: "Garment status"))
        }
        if case .unavailable(let until) = garment.availability {
            if let until, until > now {
                let date = ShortDateText.format(until, now: now, calendar: calendar, locale: locale)
                parts.append(
                    String(
                        localized: "Away until \(date)", bundle: .module,
                        comment: "Garment status: lent out or at the tailor until a date, such as Oct 23"))
            } else if until == nil {
                parts.append(
                    String(localized: "Away for now", bundle: .module, comment: "Garment status: away, no return date"))
            }
        }
        if tracksLaundry {
            parts.append(
                garment.laundry == .dirty
                    ? String(localized: "Dirty", bundle: .module, comment: "Garment status: in the wash")
                    : String(localized: "Clean", bundle: .module, comment: "Garment status: laundry tracking on"))
        }
        if parts.isEmpty {
            return String(localized: "Available", bundle: .module, comment: "Garment status: nothing in the way")
        }
        return parts.joined(separator: " · ")
    }

    /// "In 2 saved looks", or "Not in a saved look yet".
    func savedLooks(_ count: Int) -> String {
        if count == 0 {
            return String(
                localized: "Not in a saved look yet", bundle: .module, comment: "Garment detail: no saved looks use it")
        }
        return String(
            localized: "In \(count) saved looks", bundle: .module,
            comment: "Garment detail: how many saved looks use this piece")
    }

    // MARK: Removing (LR-16)

    /// When Recently deleted would let it go if she deleted it now (PRD §7.4: 30 days).
    var deletionDeadline: String {
        let deadline = now.addingTimeInterval(Garment.recentlyDeletedDays * 86_400)
        return ShortDateText.format(deadline, now: now, calendar: calendar, locale: locale)
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
