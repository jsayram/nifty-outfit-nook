import Foundation
import Models
import NookTestSupport
import Testing

struct WearRulesTests {
    private func isRecent(_ daysAgo: Int, _ window: RepeatWindow) -> Bool {
        WearRules.isRecent(TestTime.day(-daysAgo), window: window, now: TestTime.now, calendar: TestTime.calendar)
    }

    @Test func oneWeekCoversTodayAndTheSixDaysBefore() {
        #expect(isRecent(0, .oneWeek))
        #expect(isRecent(5, .oneWeek))  // LR-10.2
        #expect(isRecent(6, .oneWeek))
        #expect(!isRecent(7, .oneWeek))
    }

    @Test func twoWeeksCoversThirteenDays() {
        #expect(isRecent(10, .twoWeeks))
        #expect(isRecent(13, .twoWeeks))
        #expect(!isRecent(14, .twoWeeks))
    }

    @Test func iDontMindSkipsNothing() {
        #expect(!isRecent(0, .noLimit))  // LR-10.3
        #expect(!isRecent(3, .noLimit))
    }

    @Test func aFutureDateIsNotAWear() {
        #expect(!isRecent(-1, .oneWeek))
    }

    @Test func countsCalendarDaysNotHours() throws {
        // Late last night is yesterday, even though it's under 24 hours ago.
        let lateYesterday = try #require(TestTime.calendar.date(byAdding: .hour, value: -13, to: TestTime.now))
        #expect(WearRules.days(from: lateYesterday, to: TestTime.now, calendar: TestTime.calendar) == 1)
    }

    @Test func recordsAtMostOneWearPerDay() {
        var dates = WearRules.recording(TestTime.day(-2), in: [], calendar: TestTime.calendar)
        dates = WearRules.recording(TestTime.day(-5), in: dates, calendar: TestTime.calendar)
        let laterSameDay = TestTime.day(-2).addingTimeInterval(3_600)
        dates = WearRules.recording(laterSameDay, in: dates, calendar: TestTime.calendar)
        #expect(dates == [TestTime.day(-5), TestTime.day(-2)])
    }

    @Test func undoRemovesThatDayOnly() {
        let dates = [TestTime.day(-5), TestTime.day(-2)]
        #expect(WearRules.removing(TestTime.day(-2), from: dates, calendar: TestTime.calendar) == [TestTime.day(-5)])
    }

    @Test func recentCombinationsUseMainPiecesOnly() {
        let categories: [Garment.ID: GarmentCategory] = [
            "top": .top, "bottom": .bottom, "shoes": .shoes, "dress": .dress, "layer": .layer,
        ]
        let looks = [
            Make.look(
                "o-1", garments: ["layer", "top", "bottom", "shoes"], wornOn: [TestTime.day(-9), TestTime.day(-3)]),
            Make.look("o-2", garments: ["dress", "shoes"], wornOn: [TestTime.day(-8)]),
            Make.look("o-3", garments: ["top", "bottom"], wornOn: [TestTime.day(-1)]),
            Make.look("o-4", garments: ["shoes", "layer"], wornOn: [TestTime.day(-1)]),
        ]
        let recent = WearRules.recentCombinations(
            in: looks,
            categories: categories,
            window: .oneWeek,
            now: TestTime.now,
            calendar: TestTime.calendar
        )
        // o-1 and o-3 share main pieces, so the later wear wins. o-2 is outside the week, and
        // o-4 has no main pieces: shoes and layers can repeat.
        #expect(recent == [["top", "bottom"]: TestTime.day(-1)])
    }
}
