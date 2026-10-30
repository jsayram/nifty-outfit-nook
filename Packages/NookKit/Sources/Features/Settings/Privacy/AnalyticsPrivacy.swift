import DesignSystem
import Models
import SwiftUI

/// "Help improve the app" (F1, D24, PRD 23): the words from closet
/// `compliance/IN_APP_PRIVACY_TEXT.md` ("The analytics switch"). Off by default; the version they
/// belong to is `AnalyticsSettings.currentVersion`.
nonisolated enum AnalyticsText {
    static var title: String {
        String(localized: "Help improve the app?", bundle: .module, comment: "Analytics consent: title")
    }

    static var whatsSent: String {
        String(
            localized:
                "If you turn this on, the app sends simple events, like “Style Me finished”, with the app version and a random ID you can reset. That shows us what works and what breaks.",
            bundle: .module, comment: "Analytics consent: what is sent")
    }

    static var neverSent: String {
        String(
            localized: "Never sent: what you type, your photos, measurements, closet, looks or location.",
            bundle: .module, comment: "Analytics consent: what is never sent")
    }

    static var kept: String {
        String(
            localized: "Kept for 30 days, then only totals. Turning it off changes nothing else in the app.",
            bundle: .module, comment: "Analytics consent: how long, and that nothing else changes")
    }

    static var turnOn: String {
        String(localized: "Turn on", bundle: .module, comment: "Analytics consent: agree")
    }

    static var notNow: String {
        String(localized: "Not now", bundle: .module, comment: "Analytics consent: decline")
    }

    static var header: String {
        String(localized: "Improving the app", bundle: .module, comment: "Privacy and terms: section header (F1)")
    }

    static var switchTitle: String {
        String(localized: "Help improve the app", bundle: .module, comment: "Privacy and terms: the analytics switch")
    }

    static var switchDetail: String {
        String(
            localized: "Simple events with a random ID. Never what you type, your photos, measurements or closet.",
            bundle: .module, comment: "Privacy and terms: under the analytics switch")
    }

    static var resetID: String {
        String(localized: "Reset analytics ID", bundle: .module, comment: "Privacy and terms: analytics action")
    }

    static var resetDone: String {
        String(
            localized: "Your analytics ID is new.", bundle: .module,
            comment: "Privacy and terms: after Reset analytics ID")
    }

    static var deleteData: String {
        String(localized: "Delete my analytics data", bundle: .module, comment: "Privacy and terms: analytics action")
    }

    static var deleteDone: String {
        String(
            localized: "Your analytics data is deleted, and your analytics ID is new.", bundle: .module,
            comment: "Privacy and terms: after Delete my analytics data")
    }

    static var deleteFailed: String {
        String(
            localized: "Your analytics data couldn’t be deleted right now. Try again when you’re online.",
            bundle: .module, comment: "Privacy and terms: Delete my analytics data didn't reach the server")
    }
}

/// The consent: what goes, then Turn on or Not now. Nothing is recorded until Turn on.
struct AnalyticsConsentSheet: View {
    let turnOn: () -> Void
    let notNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                ForEach([AnalyticsText.whatsSent, AnalyticsText.neverSent, AnalyticsText.kept], id: \.self) { line in
                    Text(line)
                        .nookTextStyle(.body)
                        .foregroundStyle(.nook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: NookSpacing.small) {
                    NookButton(AnalyticsText.turnOn, kind: .primary, fillsWidth: true, action: turnOn)
                        .accessibilityIdentifier("analyticsConsent.turnOn")
                    NookButton(AnalyticsText.notNow, kind: .soft, fillsWidth: true, action: notNow)
                        .accessibilityIdentifier("analyticsConsent.notNow")
                }
            }
            .padding(NookSpacing.medium)
        }
        .accessibilityIdentifier("analyticsConsent")
    }
}

/// Privacy and terms' analytics switch, with Reset analytics ID and Delete my analytics data.
struct AnalyticsPrivacy {
    var isOn: Bool
    /// What the last action said, if anything.
    var note: String?
    var set: @MainActor @Sendable (Bool) -> Void
    var resetID: @MainActor @Sendable () -> Void = {}
    var deleteData: @MainActor @Sendable () -> Void = {}
}

struct AnalyticsPrivacyGroup: View {
    let analytics: AnalyticsPrivacy

    var body: some View {
        SettingsGroup(header: AnalyticsText.header, identifier: "privacy.analytics") {
            SettingsSwitchRow(
                title: AnalyticsText.switchTitle, detail: AnalyticsText.switchDetail, systemImage: "chart.bar",
                isOn: analytics.isOn, identifier: "privacy.analytics.switch", set: analytics.set)
            if analytics.isOn {
                Button(action: analytics.resetID) {
                    NookRow(AnalyticsText.resetID, systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.nookRow)
                .accessibilityIdentifier("privacy.analytics.reset")
                Button(action: analytics.deleteData) {
                    NookRow(AnalyticsText.deleteData, systemImage: "trash")
                }
                .buttonStyle(.nookRow)
                .accessibilityIdentifier("privacy.analytics.delete")
            }
            if let note = analytics.note {
                SettingsNote(note)
                    .accessibilityIdentifier("privacy.analytics.note")
            }
        }
    }
}
