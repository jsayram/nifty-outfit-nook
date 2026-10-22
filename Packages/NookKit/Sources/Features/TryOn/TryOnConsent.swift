import DesignSystem
import Models
import SwiftUI

/// 33a: the words for try-on's own consent, from closet `compliance/IN_APP_PRIVACY_TEXT.md`
/// ("Phase 33a to 33c"). The bold sentence is Jose's approved D1 wording, word for word.
nonisolated enum TryOnConsentText {
    static var title: String {
        String(localized: "How try-on pictures work", bundle: .module, comment: "Try-on consent: title")
    }

    static var faceStays: String {
        String(
            localized:
                "Your face never leaves your iPhone. Before anything is sent, your iPhone covers your head and hair and puts you on a plain studio backdrop. If it can’t do that, nothing is sent.",
            bundle: .module, comment: "Try-on consent")
    }

    /// The approved D1 sentence (THREAT_MODEL.md D1), word for word.
    static var whatGoes: String {
        String(
            localized:
                "A photo of your body, without your face and on a plain backdrop, and your clothing photos go to Black Forest Labs, who may keep them and use them to improve their models.",
            bundle: .module, comment: "Try-on consent: the approved disclosure, word for word")
    }

    static var comesBack: String {
        String(
            localized:
                "They send back the dressed picture, and your iPhone puts your face back in. The finished picture is saved only on your iPhone (and your iCloud if sync is on). Our server keeps the photos, encrypted, for up to 30 minutes while your picture is made, then deletes them.",
            bundle: .module, comment: "Try-on consent")
    }

    static var neverSent: String {
        String(
            localized: "Never sent: your face, your room, your measurements, your notes, your name.", bundle: .module,
            comment: "Try-on consent")
    }

    static var cantDelete: String {
        String(
            localized: "We can’t delete copies Black Forest Labs keeps.", bundle: .module, comment: "Try-on consent")
    }

    static var seeWhatWasSentNote: String {
        String(
            localized: "Each picture shows “See what was sent”, so you can check exactly what left your iPhone.",
            bundle: .module, comment: "Try-on consent")
    }

    static var turnOff: String {
        String(
            localized: "You can turn this off any time in Privacy and terms.", bundle: .module,
            comment: "Try-on consent: under the buttons")
    }

    static var allow: String {
        String(localized: "Allow", bundle: .module, comment: "Try-on consent: agree")
    }

    static var notNow: String {
        String(localized: "Not now", bundle: .module, comment: "Try-on consent: decline")
    }

    /// The line under every real picture and on "See what was sent".
    static var underPicture: String {
        String(
            localized:
                "Your face never leaves your phone. A photo of your body, without your face and on a plain backdrop, and your clothing photos go to Black Forest Labs, who may keep them and use them to improve their models.",
            bundle: .module, comment: "Under every try-on picture (33a)")
    }

    static var switchTitle: String {
        String(localized: "Try-on pictures", bundle: .module, comment: "Privacy and terms: the try-on switch")
    }

    static var switchDetail: String {
        String(
            localized:
                "A photo of your body, without your face and on a plain backdrop, and that look’s piece photos, only when you tap Try it on. Your face never leaves your iPhone.",
            bundle: .module, comment: "Privacy and terms: under the try-on switch")
    }

    static var offNote: String {
        String(
            localized:
                "Try-on pictures are off. Nothing more will be sent. Your pictures stay in the app. Black Forest Labs may keep what it already received.",
            bundle: .module, comment: "Privacy and terms: the try-on switch is off")
    }

    static var header: String {
        String(localized: "Try it on", bundle: .module, comment: "Privacy and terms: section header (33a)")
    }
}

/// The consent: what goes where, then Allow or Not now. Nothing is prepared or sent until Allow.
struct TryOnConsentContent: View {
    let allow: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            Text(TryOnConsentText.title)
                .nookTextStyle(.headline)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            paragraph(TryOnConsentText.faceStays)
            Text(TryOnConsentText.whatGoes)
                .nookTextStyle(.body)
                .bold()
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("tryOnConsent.disclosure")
            paragraph(TryOnConsentText.comesBack)
            paragraph(TryOnConsentText.neverSent)
            paragraph(TryOnConsentText.cantDelete)
            paragraph(TryOnConsentText.seeWhatWasSentNote)
            VStack(spacing: NookSpacing.small) {
                NookButton(TryOnConsentText.allow, kind: .primary, fillsWidth: true, action: allow)
                    .accessibilityIdentifier("tryOnConsent.allow")
                NookButton(TryOnConsentText.notNow, kind: .soft, fillsWidth: true, action: notNow)
                    .accessibilityIdentifier("tryOnConsent.notNow")
            }
            Text(TryOnConsentText.turnOff)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tryOnConsent")
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Privacy and terms' try-on switch (33a), shown once pictures are real.
struct TryOnPrivacy {
    var isOn: Bool
    var set: @MainActor @Sendable (Bool) -> Void
}

struct TryOnPrivacyGroup: View {
    let tryOn: TryOnPrivacy

    var body: some View {
        SettingsGroup(header: TryOnConsentText.header, identifier: "privacy.tryOn") {
            SettingsSwitchRow(
                title: TryOnConsentText.switchTitle, detail: TryOnConsentText.switchDetail, systemImage: "camera",
                isOn: tryOn.isOn, identifier: "privacy.tryOn.switch", set: tryOn.set)
            if !tryOn.isOn {
                SettingsNote(TryOnConsentText.offNote)
                    .accessibilityIdentifier("privacy.tryOn.off")
            }
        }
    }
}
