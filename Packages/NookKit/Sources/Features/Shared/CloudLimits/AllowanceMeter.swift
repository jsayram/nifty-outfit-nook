import Models
import SwiftUI

/// How much of one cloud allowance is left today, and when more comes back (Phase 24b, PRD 11.6:
/// "display category-specific remaining allowance and reset"). Made for the stylist (27a) and
/// try-on (33a) screens; the debug limits screen shows it until then.
public struct AllowanceMeter: View {
    let allowance: UsageAllowance
    let paused: Bool
    let now: Date

    public init(_ allowance: UsageAllowance, paused: Bool = false, now: Date = Date()) {
        self.allowance = allowance
        self.paused = paused
        self.now = now
    }

    public var body: some View {
        let limit = max(1, min(allowance.limitToday, allowance.limitThisMonth))
        VStack(alignment: .leading, spacing: 4) {
            Gauge(value: Double(allowance.remainingToday), in: 0...Double(limit)) {
                Text(verbatim: CloudLimitText.name(allowance.category))
            } currentValueLabel: {
                Text(verbatim: remainingText)
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(paused || allowance.remainingToday == 0 ? .secondary : .accentColor)
            Text(verbatim: detailText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: CloudLimitText.name(allowance.category)))
        .accessibilityValue(Text(verbatim: remainingText + ". " + detailText))
    }

    private var remainingText: String {
        let left = allowance.remainingToday
        let limit = allowance.limitToday
        return String(
            localized: "\(left) of \(limit) left today", bundle: .module,
            comment: "Cloud allowance meter: how many are left today, out of today's limit")
    }

    private var detailText: String {
        if paused {
            return String(
                localized: "Taking a break right now", bundle: .module,
                comment: "Cloud allowance meter: switched off on the server")
        }
        guard let resetsAt = allowance.resetsAt else {
            return String(
                localized: "None used today", bundle: .module,
                comment: "Cloud allowance meter: nothing used in the last day")
        }
        let when = CloudLimitText.whenText(resetsAt, now: now, calendar: .current)
        return allowance.remainingToday == 0
            ? String(
                localized: "More \(when)", bundle: .module,
                comment: "Cloud allowance meter: used up; when more comes back")
            : String(
                localized: "One more comes back \(when)", bundle: .module,
                comment: "Cloud allowance meter: when the oldest use stops counting")
    }
}
