import Foundation
import Models

/// What she reads when the server's limits stop a cloud action (Phase 24b, PRD 11.6: tell a
/// throttle, a used-up allowance, a pause and a failure apart, and say when it comes back). The
/// stylist (27a) and try-on (33a) show these; her closet keeps working in every case.
nonisolated public enum CloudLimitText {
    public static func message(for problem: CloudLimitProblem, now: Date = Date(), calendar: Calendar = .current)
        -> String
    {
        switch problem {
        case .rateLimited(let seconds):
            let wait = waitText(seconds)
            return String(
                localized: "You've asked a lot in the last minute. Try again in \(wait).", bundle: .module,
                comment: "Cloud limit: too many requests in a short time. The argument is a wait, like '12 seconds'.")
        case .quotaExceeded(let category, let resetAt):
            let when = whenText(resetAt, now: now, calendar: calendar)
            switch category {
            case .styleFull:
                return String(
                    localized: "You've used your outfit ideas for now. More \(when).", bundle: .module,
                    comment:
                        "Cloud limit: the full-outfit allowance is used up. The argument is like 'tomorrow at 9:15 AM'."
                )
            case .styleQuick:
                return String(
                    localized: "You've used your swaps and questions for now. More \(when).", bundle: .module,
                    comment:
                        "Cloud limit: the swap and Ask the stylist allowance is used up. The argument is like 'at 9:15 AM'."
                )
            case .tryOn:
                return String(
                    localized: "You've used your try-on pictures for now. More \(when).", bundle: .module,
                    comment: "Cloud limit: the try-on allowance is used up. The argument is like 'tomorrow at 9:15 AM'."
                )
            case .monthlySpend:
                return String(
                    localized: "You've reached this month's limit for cloud styling. It frees up \(when).",
                    bundle: .module,
                    comment: "Cloud limit: the account's monthly limit is reached. The argument is like 'on Nov 3'.")
            }
        case .paused(.style, _):
            return String(
                localized: "The stylist is taking a break. Your closet and looks work as usual.", bundle: .module,
                comment: "Cloud limit: the stylist is switched off on the server")
        case .paused(.tryOn, _):
            return String(
                localized: "Try-on pictures are taking a break. Everything else works as usual.", bundle: .module,
                comment: "Cloud limit: try-on is switched off on the server")
        case .paused(nil, _):
            return String(
                localized: "This is taking a break. Everything else works as usual.", bundle: .module,
                comment: "Cloud limit: a cloud feature is switched off on the server")
        case .busy:
            return String(
                localized: "Still working on your last request. Try again in a moment.", bundle: .module,
                comment: "Cloud limit: another cloud request is still running")
        case .deviceNotVerified:
            return String(
                localized:
                    "This iPhone couldn't be checked, so cloud styling isn't available on it. Your closet works as usual.",
                bundle: .module, comment: "Cloud limit: App Attest isn't available or failed on this device")
        case .didNotFinish:
            return String(
                localized: "That didn't finish. Try again in a minute. It won't be counted twice.", bundle: .module,
                comment: "Cloud limit: the cloud job failed or its result is still being checked")
        case .account(.offline):
            return String(
                localized: "You're offline. Your closet still works on this iPhone.", bundle: .module,
                comment: "Cloud action: no connection")
        case .account(.signedOut), .account(.cancelled):
            return String(
                localized: "Sign in to use cloud styling.", bundle: .module, comment: "Cloud action: signed out")
        case .account(.updateRequired):
            return String(
                localized: "Update the app to keep using cloud styling.", bundle: .module,
                comment: "Cloud action: this app version is too old for the server")
        case .account:
            return String(
                localized: "Something went wrong. Try again later.", bundle: .module,
                comment: "Cloud action: any other failure")
        }
    }

    /// "1 second", "12 seconds", "3 minutes".
    static func waitText(_ seconds: Int) -> String {
        if seconds < 90 {
            return Duration.seconds(max(1, seconds)).formatted(.units(allowed: [.seconds], width: .wide))
        }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .wide))
    }

    /// "at 9:15 AM" today, "tomorrow at 9:15 AM", otherwise "on Nov 3".
    static func whenText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).hour().minute())
        if calendar.isDate(date, inSameDayAs: now) {
            return String(
                localized: "at \(time)", bundle: .module, comment: "When a cloud allowance comes back, later today")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return String(
                localized: "tomorrow at \(time)", bundle: .module,
                comment: "When a cloud allowance comes back, tomorrow")
        }
        let day = date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
        return String(
            localized: "on \(day)", bundle: .module, comment: "When a cloud allowance comes back, a later day")
    }

    /// A category's name, for the allowance meter.
    public static func name(_ category: UsageCategory) -> String {
        switch category {
        case .styleFull:
            String(localized: "Outfit ideas", bundle: .module, comment: "Cloud allowance: full outfit generations")
        case .styleQuick:
            String(
                localized: "Swaps and questions", bundle: .module, comment: "Cloud allowance: swaps and Ask the stylist"
            )
        case .tryOn:
            String(localized: "Try-on pictures", bundle: .module, comment: "Cloud allowance: try-on pictures")
        case .monthlySpend:
            String(
                localized: "Cloud styling this month", bundle: .module, comment: "Cloud allowance: the monthly limit")
        }
    }
}
