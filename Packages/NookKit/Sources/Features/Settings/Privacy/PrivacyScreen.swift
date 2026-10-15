import DesignSystem
import SwiftUI

/// Privacy and terms (RD-10, `privacy.html`): the bottom desk drawer, also on Profile.
///
/// A plain summary of `closet/DATA_MAP.md` for this build: what stays on the phone, what later
/// features would send and only if she allows them, Delete my data, and the privacy policy and
/// terms on the website, opened in an in-app Safari view.
///
/// The mockup's permission switches (Style Me, Ask stylist, Try-on, Describe my photos, Weather,
/// analytics) aren't here: nothing is sent in Stage A, so a switch would control nothing. They
/// arrive with the features that need them (19b, 24a, 27a, 29, 31, 33). Export a copy waits for
/// 20b/21b.
struct PrivacyScreen: View {
    @State private var showsDeleteData = false
    @State private var page: WebsiteLink?

    var body: some View {
        PrivacyPage(
            deleteData: { showsDeleteData = true },
            open: { page = $0 }
        )
        .navigationTitle(SettingsText.privacyTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is on the wall, as on Profile.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .navigationDestination(isPresented: $showsDeleteData) {
            DeleteDataScreen()
        }
        .fullScreenCover(item: $page) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }
}

/// Privacy and terms, top to bottom. Separate from `PrivacyScreen` so snapshot tests can draw it.
struct PrivacyPage: View {
    var deleteData: () -> Void = {}
    var open: (WebsiteLink) -> Void = { _ in }

    var body: some View {
        SettingsPage(
            header: SettingsHeader(
                title: SettingsText.privacyTitle, lede: SettingsText.privacyLede, art: .drawersPrivacy)
        ) {
            NookBanner(PrivacyText.testBuild, systemImage: "info.circle", tone: .warning)
                .accessibilityIdentifier("privacy.testBuild")

            SettingsGroup(header: PrivacyText.staysHeader, identifier: "privacy.stays") {
                ForEach(PrivacyText.stays, id: \.title) { item in
                    SettingsInfoRow(title: item.title, systemImage: item.systemImage)
                }
                SettingsNote(PrivacyText.staysNote)
            }

            SettingsGroup(header: PrivacyText.laterHeader, identifier: "privacy.later") {
                SettingsNote(PrivacyText.laterNote)
                ForEach(PrivacyText.later, id: \.title) { item in
                    SettingsInfoRow(title: item.title, detail: item.detail, systemImage: item.systemImage)
                }
            }

            SettingsGroup(header: PrivacyText.yourDataHeader) {
                Button(action: deleteData) {
                    NookRow(
                        SettingsText.deleteTitle, subtitle: PrivacyText.deleteDetail, systemImage: "trash",
                        accessory: .chevron)
                }
                .buttonStyle(.nookRow)
                .accessibilityIdentifier("privacy.deleteData")
            }

            SettingsGroup(header: PrivacyText.policiesHeader) {
                ForEach(WebsiteLink.allCases) { link in
                    Button {
                        open(link)
                    } label: {
                        NookRow(
                            link.title, subtitle: PrivacyText.onTheWebsite, systemImage: link.systemImage,
                            accessory: .chevron)
                    }
                    .buttonStyle(.nookRow)
                    .accessibilityHint(Text(PrivacyText.opensWebsite))
                    .accessibilityIdentifier("privacy.\(link.rawValue)")
                }
                SettingsNote(PrivacyText.policiesNote)
            }
        }
    }
}

/// A line in one of Privacy and terms' lists.
nonisolated struct PrivacyItem: Sendable {
    let title: String
    var detail: String?
    let systemImage: String
}

/// The words on Privacy and terms, in plain language, from `closet/DATA_MAP.md`.
nonisolated enum PrivacyText {
    static var testBuild: String {
        String(
            localized:
                "This is a test build. It has no account, the app sends nothing, and there’s no tracking or analytics.",
            bundle: .module, comment: "Privacy and terms: the banner at the top")
    }

    static var staysHeader: String {
        String(localized: "Stays on this iPhone", bundle: .module, comment: "Privacy and terms: section header")
    }

    static var stays: [PrivacyItem] {
        [
            PrivacyItem(
                title: String(
                    localized: "Your pieces, their pictures and details", bundle: .module,
                    comment: "Privacy and terms: what stays on the iPhone"),
                systemImage: "hanger"),
            PrivacyItem(
                title: String(
                    localized: "Suitcases and laundry marks", bundle: .module,
                    comment: "Privacy and terms: what stays on the iPhone"),
                systemImage: "suitcase"),
            PrivacyItem(
                title: String(
                    localized: "Saved looks and try-on pictures", bundle: .module,
                    comment: "Privacy and terms: what stays on the iPhone"),
                systemImage: "bookmark"),
            PrivacyItem(
                title: String(
                    localized: "Your name, measurements, weight and fit", bundle: .module,
                    comment: "Privacy and terms: what stays on the iPhone"),
                systemImage: "ruler"),
            PrivacyItem(
                title: String(
                    localized: "Preferences and what Style Me remembers", bundle: .module,
                    comment: "Privacy and terms: what stays on the iPhone"),
                systemImage: "slider.horizontal.3"),
        ]
    }

    static var staysNote: String {
        String(
            localized:
                "Fit and measurements and your try-on pictures are hidden when you switch apps. This test build keeps everything only while the app is open, so closing it brings back the sample closet.",
            bundle: .module, comment: "Privacy and terms: under what stays on the iPhone")
    }

    static var laterHeader: String {
        String(
            localized: "Later, sent only if you allow it", bundle: .module,
            comment: "Privacy and terms: section header")
    }

    static var laterNote: String {
        String(
            localized:
                "None of these is in this test build. Each will ask first, and allowing one never allows another.",
            bundle: .module, comment: "Privacy and terms: above what later features would send")
    }

    static var later: [PrivacyItem] {
        [
            PrivacyItem(
                title: String(
                    localized: "Style Me and swaps", bundle: .module, comment: "Privacy and terms: a later feature"),
                detail: String(
                    localized:
                        "Piece names, kinds and colours, the occasion and the weather, when you tap Style me. Never your photos or your name.",
                    bundle: .module, comment: "Privacy and terms: what Style Me would send"),
                systemImage: "sparkles"),
            PrivacyItem(
                title: String(
                    localized: "Try-on pictures", bundle: .module, comment: "Privacy and terms: a later feature"),
                detail: String(
                    localized:
                        "That look’s piece photos and your try-on photo, only when you tap Try it on, with its own permission.",
                    bundle: .module, comment: "Privacy and terms: what Try it on would send"),
                systemImage: "camera"),
            PrivacyItem(
                title: String(localized: "Weather", bundle: .module, comment: "Privacy and terms: a later feature"),
                detail: String(
                    localized: "A rough location for the forecast. Never your exact address.", bundle: .module,
                    comment: "Privacy and terms: what weather would send"),
                systemImage: "cloud.sun"),
        ]
    }

    static var yourDataHeader: String {
        String(localized: "Your data", bundle: .module, comment: "Privacy and terms: section header")
    }

    static var deleteDetail: String {
        String(
            localized: "Everything you’ve added, from this iPhone", bundle: .module,
            comment: "Privacy and terms: under the Delete my data row")
    }

    static var policiesHeader: String {
        String(localized: "Policies", bundle: .module, comment: "Privacy and terms: section header")
    }

    static var onTheWebsite: String {
        String(localized: "On the website", bundle: .module, comment: "Privacy and terms: under a policy row")
    }

    static var opensWebsite: String {
        String(
            localized: "Opens the page on the app’s website.", bundle: .module,
            comment: "VoiceOver hint on the privacy policy and terms rows")
    }

    static var policiesNote: String {
        String(
            localized: "The full privacy policy and terms are still being written.", bundle: .module,
            comment: "Privacy and terms: under the policy rows, before the pages exist")
    }
}

extension WebsiteLink {
    var title: String {
        switch self {
        case .privacyPolicy:
            String(localized: "Privacy policy", bundle: .module, comment: "Privacy and terms: a row")
        case .terms: String(localized: "Terms of use", bundle: .module, comment: "Privacy and terms: a row")
        }
    }

    var systemImage: String {
        switch self {
        case .privacyPolicy: "lock"
        case .terms: "doc.text"
        }
    }
}
