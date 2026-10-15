import Foundation
import Models

/// One piece as the Closet grid shows it, worked out once when the closet loads so a cell does
/// no lookups of its own: its suitcases' names (LR-11), whether it's in the wash (only while
/// laundry tracking is on, RD-11) and when she last wore it (LR-10).
nonisolated struct ClosetItem: Identifiable, Hashable, Sendable {
    let id: Garment.ID
    let name: String
    let category: GarmentCategory
    let colors: [ColorName]
    let photo: PhotoReference
    let cutout: GarmentCutout?
    /// The active suitcases it's packed in, by name. A packed piece shows one small suitcase
    /// icon however many there are, and VoiceOver reads every name (LR-11.1).
    let suitcaseNames: [String]
    /// In the wash, shown only while laundry tracking is on (RD-11).
    let isDirty: Bool
    let lastWorn: Date?
    /// A short mark under the name in a picker, such as "May not match" (Phase 11).
    let note: String?

    init(_ garment: Garment, suitcaseNames: [String], tracksLaundry: Bool, note: String? = nil) {
        id = garment.id
        name = garment.name
        category = garment.category
        colors = garment.colors
        photo = garment.photo
        cutout = garment.cutout
        self.suitcaseNames = suitcaseNames
        isDirty = tracksLaundry && garment.laundry == .dirty
        lastWorn = garment.lastWorn
        self.note = note
    }

    var isPacked: Bool { !suitcaseNames.isEmpty }

    /// What VoiceOver reads after the name: "Dirty, In Weekend and Jose's house, Last worn
    /// 3 days ago". Built when a cell shows, not for every piece up front.
    func spokenDetails(now: Date, calendar: Calendar, locale: Locale) -> String {
        var parts: [String] = []
        if let note { parts.append(note) }
        if isDirty {
            parts.append(String(localized: "Dirty", bundle: .module, comment: "Spoken on a closet piece in the wash"))
        }
        if isPacked {
            let names = suitcaseNames.formatted(.list(type: .and).locale(locale))
            parts.append(
                String(
                    localized: "In \(names)", bundle: .module,
                    comment: "Spoken on a packed closet piece: the suitcases it's in, as in In Weekend and Gym"))
        }
        if let lastWorn {
            parts.append(LastWornText.describe(lastWorn, now: now, calendar: calendar, locale: locale))
        }
        return parts.joined(separator: ", ")
    }
}

/// "Last worn 3 days ago", "Last worn yesterday", "Last worn 3 Oct" (LR-10).
nonisolated enum LastWornText {
    /// Counts calendar days, so something worn late last night is "yesterday". Within a week it
    /// says how many days ago; after that it gives the date.
    static func describe(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        switch days {
        case ..<1:
            return String(localized: "Last worn today", bundle: .module, comment: "When a piece was last worn")
        case 1:
            return String(localized: "Last worn yesterday", bundle: .module, comment: "When a piece was last worn")
        case 2..<7:
            return String(
                localized: "Last worn \(days) days ago", bundle: .module,
                comment: "When a piece was last worn, 2 to 6 days ago")
        default:
            let formatted = ShortDateText.format(date, now: now, calendar: calendar, locale: locale)
            return String(
                localized: "Last worn \(formatted)", bundle: .module,
                comment: "When a piece was last worn, a week ago or more: a date such as 3 Oct")
        }
    }
}

/// A day and short month ("Oct 3", or "3 Oct" where that's the order), with the year only when
/// it isn't this year's. For Last worn, Away until and Recently deleted's deadlines.
nonisolated enum ShortDateText {
    static func format(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar)
            .day().month(.abbreviated)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
