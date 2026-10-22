import DesignSystem
import Models
import SwiftUI

/// Privacy and terms (RD-10, `privacy.html`): the bottom desk drawer, also on Profile.
///
/// A plain summary of `closet/DATA_MAP.md` for this build: what stays on the phone, what later
/// features would send and only if she allows them, Delete my data, and the privacy policy and
/// terms on the website, opened in an in-app Safari view.
///
/// The mockup's permission switches (Style Me, Ask stylist, Try-on, Describe my photos, Weather,
/// analytics) aren't here: nothing is sent in Stage A, so a switch would control nothing. They
/// arrive with the features that need them (19b, 24a, 27a, 29, 31, 33). Backups (export and
/// restore) sits in Your data since Phase 21b, where her closet is in the store.
struct PrivacyScreen: View {
    @Environment(\.services) private var services
    @State private var showsDeleteData = false
    @State private var showsDeleteAccount = false
    @State private var showsBackups = false
    @State private var page: WebsiteLink?
    @State private var weather = WeatherSettingsModel()
    @Environment(\.openURL) private var openURL
    /// Delete my account is offered only while she's signed in (24c).
    @State private var isSignedIn = false
    /// 27a: her yes to the cloud stylist, and the consent sheet the switch opens.
    @State private var stylistOn = false
    @State private var showsStylistConsent = false
    /// 33a: her yes to try-on's image provider, and the consent the switch opens.
    @State private var tryOnOn = false
    @State private var showsTryOnConsent = false

    var body: some View {
        PrivacyPage(
            keepsChanges: services.keepsChanges,
            backups: services.backups == nil ? nil : { showsBackups = true },
            deleteData: { showsDeleteData = true },
            deleteAccount: isSignedIn ? { showsDeleteAccount = true } : nil,
            open: { page = $0 },
            weather: weatherContent,
            stylist: services.cloudStyling ? stylistContent : nil,
            tryOn: services.tryOnPipeline == nil ? nil : tryOnContent
        )
        .task {
            await weather.load(from: services)
            isSignedIn = await services.account.isSignedIn()
            stylistOn = services.stylistConsent.current()?.isCurrent == true
            tryOnOn = services.tryOnConsent.current()?.isCurrent == true
        }
        .nookSheet(isPresented: $showsTryOnConsent, title: TryOnConsentText.switchTitle, detents: [.large]) {
            ScrollView {
                TryOnConsentContent(
                    allow: {
                        services.tryOnConsent.save(TryOnConsent(agreedAt: .now))
                        tryOnOn = true
                        showsTryOnConsent = false
                    },
                    notNow: { showsTryOnConsent = false }
                )
                .padding(NookSpacing.medium)
            }
        }
        .nookSheet(isPresented: $showsStylistConsent, title: StylistConsentText.title, detents: [.large]) {
            StylistConsentSheet(
                allow: {
                    services.stylistConsent.save(StylistConsent(agreedAt: .now))
                    stylistOn = true
                    showsStylistConsent = false
                },
                notNow: { showsStylistConsent = false })
        }
        .alert(
            WeatherText.explainerTitle, isPresented: $weather.showsLocationExplainer,
            actions: {
                Button(WeatherText.explainerContinue) { Task { await weather.continueWithLocation() } }
                    .accessibilityIdentifier("privacy.weather.explainer.continue")
                Button(WeatherText.explainerCity) { weather.chooseCityInstead() }
                    .accessibilityIdentifier("privacy.weather.explainer.city")
            },
            message: { Text(WeatherText.explainerMessage) }
        )
        .nookSheet(
            isPresented: $weather.showsCityPicker, title: WeatherText.sheetTitle,
            subtitle: WeatherText.sheetSubtitle, detents: [.large]
        ) {
            WeatherCitySheet(model: weather)
        }
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
        .navigationDestination(isPresented: $showsDeleteAccount) {
            DeleteDataScreen(scope: .account)
        }
        .navigationDestination(isPresented: $showsBackups) {
            BackupsScreen()
        }
        .fullScreenCover(item: $page) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        // Privacy and terms' quick tour (Phase 16b).
        .screenTour(PrivacyTour.definition, isReady: !showsDeleteData && !showsBackups && page == nil)
    }

    /// 27a: turning it on shows the consent text first; turning it off withdraws at once.
    private var stylistContent: StylistPrivacy {
        StylistPrivacy(
            isOn: stylistOn,
            set: { on in
                if on {
                    showsStylistConsent = true
                } else {
                    services.stylistConsent.save(nil)
                    stylistOn = false
                }
            })
    }

    /// 33a: turning it on shows the consent first; turning it off withdraws at once. A picture
    /// already on its way still finishes; nothing more is sent.
    private var tryOnContent: TryOnPrivacy {
        TryOnPrivacy(
            isOn: tryOnOn,
            set: { on in
                if on {
                    showsTryOnConsent = true
                } else {
                    services.tryOnConsent.save(nil)
                    tryOnOn = false
                }
            })
    }

    private var weatherContent: WeatherPrivacy {
        WeatherPrivacy(
            isOn: weather.settings.isOn, usesMyLocation: weather.settings.usesMyLocation,
            cityName: weather.settings.city?.name, locationIsBlocked: weather.locationIsBlocked,
            isSample: weather.isSample, credit: weather.credit,
            setOn: { weather.setOn($0) }, setUsesMyLocation: { weather.setUsesMyLocation($0) },
            chooseCity: { weather.showsCityPicker = true },
            openSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            })
    }
}

/// Privacy and terms, top to bottom. Separate from `PrivacyScreen` so snapshot tests can draw it.
struct PrivacyPage: View {
    /// Whether her changes are kept when the app closes (`NookServices.keepsChanges`). The debug
    /// sample closet, which snapshot tests show, comes back as it ships.
    var keepsChanges = false
    /// Opens Backups (Phase 21b). `nil` hides the row: the debug sample closet has nothing to back up.
    var backups: (() -> Void)?
    var deleteData: () -> Void = {}
    /// Opens Delete my account (24c). `nil` hides the row: she isn't signed in.
    var deleteAccount: (() -> Void)?
    var open: (WebsiteLink) -> Void = { _ in }
    /// The weather rows (Phase 29). `nil` leaves them out, as the first Stage B screens drew it.
    var weather: WeatherPrivacy?
    /// The stylist's consent switch (27a). `nil` while Style Me uses the stylist on the phone.
    var stylist: StylistPrivacy?
    /// Try-on's consent switch (33a). `nil` while pictures are simulated on the phone.
    var tryOn: TryOnPrivacy?

    var body: some View {
        SettingsPage(
            header: SettingsHeader(
                title: SettingsText.privacyTitle, lede: SettingsText.privacyLede, art: .drawersPrivacy)
        ) {
            NookBanner(
                weather.map { $0.isOn && !$0.isSample } == true ? PrivacyText.testBuildWeather : PrivacyText.testBuild,
                systemImage: "info.circle", tone: .warning
            )
            .accessibilityIdentifier("privacy.testBuild")

            SettingsGroup(header: PrivacyText.staysHeader, identifier: "privacy.stays") {
                ForEach(PrivacyText.stays, id: \.title) { item in
                    SettingsInfoRow(title: item.title, systemImage: item.systemImage)
                }
                SettingsNote(keepsChanges ? PrivacyText.staysNoteKept : PrivacyText.staysNote)
            }

            if let stylist {
                StylistPrivacyGroup(stylist: stylist)
            }

            if let tryOn {
                TryOnPrivacyGroup(tryOn: tryOn)
            }

            if let weather {
                WeatherPrivacyGroup(weather: weather)
            }

            SettingsGroup(header: PrivacyText.laterHeader, identifier: "privacy.later") {
                SettingsNote(PrivacyText.laterNote)
                ForEach(
                    PrivacyText.later(
                        includingWeather: weather == nil, includingStylist: stylist == nil, includingTryOn: tryOn == nil),
                    id: \.title
                ) { item in
                    SettingsInfoRow(title: item.title, detail: item.detail, systemImage: item.systemImage)
                }
            }
            .tourAnchor(PrivacyTour.Anchor.later, label: PrivacyText.laterHeader)

            SettingsGroup(header: PrivacyText.yourDataHeader) {
                if let backups {
                    Button(action: backups) {
                        NookRow(
                            BackupsText.title, subtitle: BackupsText.rowDetail, systemImage: "externaldrive",
                            accessory: .chevron)
                    }
                    .buttonStyle(.nookRow)
                    .accessibilityIdentifier("privacy.backups")
                }
                Button(action: deleteData) {
                    NookRow(
                        SettingsText.deleteTitle, subtitle: PrivacyText.deleteDetail, systemImage: "trash",
                        accessory: .chevron)
                }
                .buttonStyle(.nookRow)
                .accessibilityIdentifier("privacy.deleteData")
                .tourAnchor(PrivacyTour.Anchor.deleteData, label: SettingsText.deleteTitle, action: deleteData)
                if let deleteAccount {
                    Button(action: deleteAccount) {
                        NookRow(
                            DeleteDataText.accountTitle, subtitle: PrivacyText.deleteAccountDetail,
                            systemImage: "person.crop.circle.badge.xmark", accessory: .chevron)
                    }
                    .buttonStyle(.nookRow)
                    .accessibilityIdentifier("privacy.deleteAccount")
                }
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
                "Fit and measurements and your try-on pictures are hidden when you switch apps. When this test build closes, it keeps the name on your sign, Preferences, Avoid repeating outfits for and Track laundry, that you’ve set it up, which closet you chose and which tips you’ve seen. Everything else goes back to how it started: the closet you chose comes back as it was, with its own fit details and try-on photo, and anything you changed in them is cleared.",
            bundle: .module, comment: "Privacy and terms: under what stays on the iPhone")
    }

    /// Since Phase 21a, for her own closet in the store on the iPhone.
    static var staysNoteKept: String {
        String(
            localized:
                "Fit and measurements and your try-on pictures are hidden when you switch apps. Everything you add or change is kept on this iPhone when the app closes, until you delete it. Delete my data removes all of it.",
            bundle: .module, comment: "Privacy and terms: under what stays on the iPhone, when her data is kept")
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

    /// What a test build says while Live weather is on, since "sends nothing" would no longer be true.
    static var testBuildWeather: String {
        String(
            localized:
                "This is a test build. It has no account and no tracking or analytics. Live weather is on, so a rough location goes to Apple Weather. Nothing else is sent.",
            bundle: .module, comment: "Privacy and terms: the banner at the top while Live weather is on")
    }

    /// Weather leaves the list once the Weather group above it is real (Phase 29), and Style Me
    /// once its switch is (27a).
    static func later(includingWeather: Bool, includingStylist: Bool = true, includingTryOn: Bool = true)
        -> [PrivacyItem]
    {
        later.filter {
            (includingWeather || $0.systemImage != "cloud.sun") && (includingStylist || $0.systemImage != "sparkles")
                && (includingTryOn || $0.systemImage != "camera")
        }
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

    static var deleteAccountDetail: String {
        String(
            localized: "Your account and what the app’s server keeps, then everything on this iPhone",
            bundle: .module, comment: "Privacy and terms: under the Delete my account row")
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

nonisolated extension WebsiteLink {
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
