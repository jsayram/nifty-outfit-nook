import Foundation

/// Wear records, Last worn and the repeat window (LR-10).
///
/// Wear is optional and explicit: only Wear today records it. Saving or picking a look is not
/// wear, and wear never changes laundry status (LR-10.4).
public enum WearRules {
    /// Kinds of piece that make up an outfit's "main-piece combination". Shoes, layers and bags
    /// can repeat freely, and so can any single favourite piece (LR-10).
    public static let mainCategories: Set<GarmentCategory> = [.top, .bottom, .dress]

    /// Whole calendar days from `earlier` to `later`. Negative when `earlier` is after `later`.
    public static func days(from earlier: Date, to later: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: earlier)
        let end = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// True when a wear on `worn` falls inside the repeat window as of `now`.
    ///
    /// With 1 week, anything worn today or in the 6 days before is recent; a week ago is not.
    /// "I don't mind" makes nothing recent (LR-10.3). A date after today is not a wear yet.
    public static func isRecent(_ worn: Date, window: RepeatWindow, now: Date, calendar: Calendar) -> Bool {
        guard let windowDays = window.days else { return false }
        let ago = days(from: worn, to: now, calendar: calendar)
        return ago >= 0 && ago < windowDays
    }

    /// Adds a wear day, keeping at most one entry per calendar day, oldest first.
    public static func recording(_ date: Date, in dates: [Date], calendar: Calendar) -> [Date] {
        guard !dates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) else { return dates }
        return (dates + [date]).sorted()
    }

    /// Removes the wear recorded on `date`'s day, for Undo (LR-10.1).
    public static func removing(_ date: Date, from dates: [Date], calendar: Calendar) -> [Date] {
        dates.filter { !calendar.isDate($0, inSameDayAs: date) }
    }

    /// The main pieces of a look: its owned tops, bottoms and dresses.
    public static func mainPieces(of look: Look, categories: [Garment.ID: GarmentCategory]) -> Set<Garment.ID> {
        Set(look.garmentIDs.filter { id in categories[id].map(mainCategories.contains) ?? false })
    }

    /// Main-piece combinations worn inside the repeat window, each with the last day it was worn.
    public static func recentCombinations(
        in looks: [Look],
        categories: [Garment.ID: GarmentCategory],
        window: RepeatWindow,
        now: Date,
        calendar: Calendar
    ) -> [Set<Garment.ID>: Date] {
        var combinations: [Set<Garment.ID>: Date] = [:]
        for look in looks {
            guard
                let lastWorn = look.wornOn.filter({ isRecent($0, window: window, now: now, calendar: calendar) }).max()
            else { continue }
            let key = mainPieces(of: look, categories: categories)
            guard !key.isEmpty else { continue }
            combinations[key] = max(combinations[key] ?? lastWorn, lastWorn)
        }
        return combinations
    }
}
