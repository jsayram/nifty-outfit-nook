import Foundation
import Models
import Testing

@testable import Features

/// What she reads for each cloud limit (Phase 24b).
struct CloudLimitTextTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    /// 21 October 2026, 10:00 in Los Angeles.
    let now = Date(timeIntervalSince1970: 1_792_602_000)

    func text(_ problem: CloudLimitProblem) -> String {
        CloudLimitText.message(for: problem, now: now, calendar: calendar)
    }

    @Test func eachLimitIsToldApart() {
        #expect(
            text(.rateLimited(retryAfterSeconds: 12))
                == "You've asked a lot in the last minute. Try again in 12 seconds.")
        #expect(text(.paused(feature: .tryOn, retryAfterSeconds: nil)).hasPrefix("Try-on pictures are taking a break."))
        #expect(text(.paused(feature: .style, retryAfterSeconds: nil)).hasPrefix("The stylist is taking a break."))
        #expect(text(.busy(retryAfterSeconds: 2)) == "Still working on your last request. Try again in a moment.")
        #expect(text(.didNotFinish(retryAfterSeconds: 30)).contains("won't be counted twice"))
        #expect(text(.deviceNotVerified).contains("couldn't be checked"))
        #expect(text(.account(.offline)).hasPrefix("You're offline."))
        // Every message is different, so she can tell a throttle from a used-up allowance or a pause.
        let all: [CloudLimitProblem] = [
            .rateLimited(retryAfterSeconds: 5), .quotaExceeded(category: .tryOn, resetAt: now),
            .paused(feature: .tryOn, retryAfterSeconds: nil), .busy(retryAfterSeconds: 1), .deviceNotVerified,
            .didNotFinish(retryAfterSeconds: nil),
        ]
        #expect(Set(all.map(text)).count == all.count)
    }

    @Test func aUsedUpAllowanceSaysWhenMoreComesBack() {
        let later = now.addingTimeInterval(3 * 3600)
        let tomorrow = now.addingTimeInterval(23 * 3600)
        let nextWeek = now.addingTimeInterval(6 * 86_400)
        #expect(
            text(.quotaExceeded(category: .tryOn, resetAt: later)).hasPrefix(
                "You've used your try-on pictures for now. More at "))
        #expect(
            text(.quotaExceeded(category: .styleFull, resetAt: tomorrow)).hasPrefix(
                "You've used your outfit ideas for now. More tomorrow at "))
        #expect(text(.quotaExceeded(category: .styleQuick, resetAt: nextWeek)).contains("More on "))
        #expect(
            text(.quotaExceeded(category: .monthlySpend, resetAt: nextWeek)).hasPrefix(
                "You've reached this month's limit"))
    }

    @Test func waitsReadNaturally() {
        #expect(CloudLimitText.waitText(1) == "1 second")
        #expect(CloudLimitText.waitText(45) == "45 seconds")
        #expect(CloudLimitText.waitText(600) == "10 minutes")
    }

    @Test func theMeterCountsWhatIsLeft() {
        let allowance = UsageAllowance(
            category: .tryOn, usedToday: 2, limitToday: 3, usedThisMonth: 29, limitThisMonth: 30, resetsAt: nil)
        // One left today, but only one left this month too.
        #expect(allowance.remainingToday == 1)
        let monthUsed = UsageAllowance(
            category: .tryOn, usedToday: 0, limitToday: 3, usedThisMonth: 30, limitThisMonth: 30, resetsAt: nil)
        #expect(monthUsed.remainingToday == 0)
    }
}
