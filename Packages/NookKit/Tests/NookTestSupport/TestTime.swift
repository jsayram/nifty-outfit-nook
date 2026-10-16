import Foundation

/// A fixed calendar, date and locale, so tests don't depend on the Mac's time zone, today's date
/// or its language.
public enum TestTime {
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Noon UTC on 14 October 2026.
    public static let now = Date(timeIntervalSince1970: 1_791_979_200)

    /// `offset` days from `now`, same time of day.
    public static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now) ?? now
    }

    /// US English, for tests of dates and counts in words.
    public static let locale = Locale(identifier: "en_US")
}
