import DesignSystem
import Models
import SwiftUI

/// The cloud stylist's consent words (Phase 27a): version A of `closet/compliance/IN_APP_PRIVACY_TEXT.md`,
/// since measurements and weight are never sent. The version they belong to is
/// `StylistConsent.currentVersion`; changing what they promise needs a new version.
nonisolated enum StylistConsentText {
    static var title: String {
        String(
            localized: "Style Me sends your request to Anthropic", bundle: .module,
            comment: "Stylist consent sheet title (27a)")
    }

    static var who: String {
        String(
            localized: "Anthropic makes Claude, the AI that suggests your outfits.", bundle: .module,
            comment: "Stylist consent: who the recipient is")
    }

    static var whatsSent: String {
        String(
            localized:
                "What’s sent, when you tap Style me, swap a piece or ask the stylist: short descriptions of the pieces involved (kind, colour, fabric, the names you gave them), the occasion, the weather (like “cool and rainy”), any note you type, and your recent looks so ideas don’t repeat.",
            bundle: .module, comment: "Stylist consent: what is sent")
    }

    static var neverSent: String {
        String(
            localized: "Never sent: your photos, your name, your measurements or weight, your location.",
            bundle: .module, comment: "Stylist consent: what is never sent")
    }

    static var keeping: String {
        String(
            localized:
                "What Anthropic does with it: doesn’t use it to train its models, and deletes it within 30 days. If its safety checks flag a request, it can keep it for up to 2 years. It may be processed outside the US.",
            bundle: .module, comment: "Stylist consent: what the recipient does with it")
    }

    static var turnOff: String {
        String(
            localized: "You can turn this off any time in Privacy and terms.", bundle: .module,
            comment: "Stylist consent: how to withdraw")
    }

    static var allow: String {
        String(localized: "Allow", bundle: .module, comment: "Stylist consent: agree")
    }

    static var notNow: String {
        String(localized: "Not now", bundle: .module, comment: "Stylist consent: decline")
    }

    /// Style Me without consent (IN_APP_PRIVACY_TEXT "If she says Not now").
    static var needsConsent: String {
        String(
            localized: "Style Me needs your OK to send your request to Anthropic. You can still make your own looks.",
            bundle: .module, comment: "Your looks without stylist consent")
    }

    static var needsConsentTitle: String {
        String(localized: "Style Me needs your OK", bundle: .module, comment: "Your looks without stylist consent")
    }

    static var review: String {
        String(localized: "Review", bundle: .module, comment: "Opens the stylist consent sheet")
    }

    static var switchTitle: String {
        String(
            localized: "Style Me, swaps and Ask stylist", bundle: .module,
            comment: "Privacy and terms: the stylist consent switch")
    }

    static var switchDetail: String {
        String(
            localized:
                "Piece descriptions, the occasion and the weather go to Anthropic when you ask. Never your photos, name, measurements or location.",
            bundle: .module, comment: "Privacy and terms: under the stylist switch")
    }

    static var offNote: String {
        String(
            localized: "Style Me is off. Your closet, saved looks and making your own looks still work.",
            bundle: .module, comment: "Privacy and terms: the stylist switch is off")
    }

    static var header: String {
        String(localized: "Style Me", bundle: .module, comment: "Privacy and terms: section header (27a)")
    }
}

/// The consent sheet: what goes where, then Allow or Not now. Nothing is sent until Allow.
struct StylistConsentSheet: View {
    let allow: () -> Void
    let notNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                ForEach(
                    [
                        StylistConsentText.who, StylistConsentText.whatsSent, StylistConsentText.neverSent,
                        StylistConsentText.keeping,
                    ], id: \.self
                ) { line in
                    Text(line)
                        .nookTextStyle(.body)
                        .foregroundStyle(.nook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: NookSpacing.small) {
                    NookButton(StylistConsentText.allow, kind: .primary, fillsWidth: true, action: allow)
                        .accessibilityIdentifier("stylistConsent.allow")
                    NookButton(StylistConsentText.notNow, kind: .soft, fillsWidth: true, action: notNow)
                        .accessibilityIdentifier("stylistConsent.notNow")
                }
                Text(StylistConsentText.turnOff)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(NookSpacing.medium)
        }
        .accessibilityIdentifier("stylistConsent")
    }
}

/// Privacy and terms' stylist switch (27a), shown once Style Me uses the cloud stylist.
struct StylistPrivacy {
    var isOn: Bool
    var set: @MainActor @Sendable (Bool) -> Void
}

struct StylistPrivacyGroup: View {
    let stylist: StylistPrivacy

    var body: some View {
        SettingsGroup(header: StylistConsentText.header, identifier: "privacy.stylist") {
            SettingsSwitchRow(
                title: StylistConsentText.switchTitle, detail: StylistConsentText.switchDetail,
                systemImage: "sparkles", isOn: stylist.isOn, identifier: "privacy.stylist.switch", set: stylist.set)
            if !stylist.isOn {
                SettingsNote(StylistConsentText.offNote)
                    .accessibilityIdentifier("privacy.stylist.off")
            }
        }
    }
}
