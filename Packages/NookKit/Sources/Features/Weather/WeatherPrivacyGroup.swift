import DesignSystem
import Models
import SwiftUI

/// What the weather rows in Privacy and terms show and do (Phase 29). Plain values and closures,
/// so snapshot tests can draw it without a model.
struct WeatherPrivacy {
    var isOn = false
    var usesMyLocation = false
    var cityName: String?
    /// iOS doesn't allow her location (she said no, or turned it off in Settings).
    var locationIsBlocked = false
    /// The weather is made up in this build (WeatherKit isn't switched on).
    var isSample = true
    var credit: WeatherCredit?

    var setOn: @MainActor @Sendable (Bool) -> Void = { _ in }
    var setUsesMyLocation: @MainActor @Sendable (Bool) -> Void = { _ in }
    var chooseCity: () -> Void = {}
    var openSettings: () -> Void = {}
}

/// Privacy and terms' Weather group: the Live weather switch, her city (no permission needed),
/// the optional approximate location, and what each one does. The words are in
/// `closet/compliance/IN_APP_PRIVACY_TEXT.md` and `PERMISSIONS.md`.
struct WeatherPrivacyGroup: View {
    let weather: WeatherPrivacy

    var body: some View {
        SettingsGroup(header: WeatherText.header, identifier: "privacy.weather") {
            SettingsSwitchRow(
                title: WeatherText.liveTitle, detail: WeatherText.liveDetail, systemImage: "cloud.sun",
                isOn: weather.isOn, identifier: "privacy.weather.live", set: weather.setOn)
            if weather.isOn {
                Button(action: weather.chooseCity) {
                    NookRow(
                        WeatherText.cityTitle, subtitle: WeatherText.cityDetail,
                        value: weather.cityName ?? WeatherText.noCity, systemImage: "building.2",
                        accessory: .chevron)
                }
                .buttonStyle(.nookRow)
                .accessibilityIdentifier("privacy.weather.city")
                SettingsSwitchRow(
                    title: WeatherText.locationTitle, detail: WeatherText.locationDetail, systemImage: "location",
                    isOn: weather.usesMyLocation, identifier: "privacy.weather.location",
                    set: weather.setUsesMyLocation)
                if weather.locationIsBlocked {
                    SettingsNote(WeatherText.blocked)
                        .accessibilityIdentifier("privacy.weather.blocked")
                    Button(action: weather.openSettings) {
                        NookRow(WeatherText.openSettings, systemImage: "gearshape", accessory: .chevron)
                    }
                    .buttonStyle(.nookRow)
                    .accessibilityIdentifier("privacy.weather.openSettings")
                }
                if weather.cityName == nil, !weather.usesMyLocation {
                    SettingsNote(WeatherText.needsPlace)
                        .accessibilityIdentifier("privacy.weather.needsPlace")
                }
            } else {
                SettingsNote(WeatherText.off)
                    .accessibilityIdentifier("privacy.weather.off")
            }
            if weather.isSample {
                SettingsNote(WeatherText.sample)
                    .accessibilityIdentifier("privacy.weather.sample")
            }
            if let credit = weather.credit {
                WeatherCreditView(credit: credit)
                    .padding(.horizontal, NookSpacing.medium)
            }
        }
    }
}

/// The city sheet: type a name, pick a match. A city needs no location permission.
struct WeatherCitySheet: View {
    @Bindable var model: WeatherSettingsModel

    @State private var text = ""
    @AccessibilityFocusState private var focus: Field?

    private enum Field: Hashable {
        case city
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            EditorTextField(
                label: WeatherText.cityTitle, prompt: WeatherText.cityPrompt, text: $text, problem: nil,
                identifier: "weather.cityField", focus: $focus, focusValue: .city)
            results
            if model.settings.city != nil {
                Button {
                    model.removeCity()
                } label: {
                    NookRow(WeatherText.removeCity, systemImage: "xmark.circle")
                }
                .buttonStyle(.nookRow)
                .accessibilityIdentifier("weather.removeCity")
            }
            Text(WeatherText.searchNote)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: text) { await model.find(text) }
    }

    @ViewBuilder private var results: some View {
        switch model.search {
        case .idle: EmptyView()
        case .searching:
            Text(WeatherText.searching).nookTextStyle(.note).foregroundStyle(.nook.textSecondary)
        case .none:
            Text(WeatherText.noMatch).nookTextStyle(.note).foregroundStyle(.nook.textSecondary)
                .accessibilityIdentifier("weather.noMatch")
        case .failed:
            Text(WeatherText.searchFailed).nookTextStyle(.note).foregroundStyle(.nook.textSecondary)
                .accessibilityIdentifier("weather.searchFailed")
        case .results(let places):
            VStack(spacing: NookSpacing.xxSmall) {
                ForEach(places, id: \.name) { place in
                    Button {
                        model.choose(place)
                    } label: {
                        NookRow(place.name, systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.nookRow)
                    .accessibilityIdentifier("weather.city.\(place.name)")
                }
            }
        }
    }
}

/// The words for the weather settings, from `closet/compliance`.
nonisolated enum WeatherText {
    static var header: String {
        String(localized: "Weather", bundle: .module, comment: "Privacy and terms: section header")
    }
    static var liveTitle: String {
        String(localized: "Live weather", bundle: .module, comment: "Privacy and terms: the weather switch")
    }
    static var liveDetail: String {
        String(
            localized:
                "A rough location goes to Apple Weather for the forecast. It isn’t saved. Only the weather goes into Style Me.",
            bundle: .module, comment: "Privacy and terms: under the Live weather switch")
    }
    static var off: String {
        String(
            localized: "Live weather is off. Home’s window stays plain and Style Me doesn’t use the weather.",
            bundle: .module, comment: "Privacy and terms: under the weather switch when it's off")
    }
    static var cityTitle: String {
        String(localized: "City", bundle: .module, comment: "Weather settings: the city row and field label")
    }
    static var cityDetail: String {
        String(
            localized: "Needs no permission.", bundle: .module,
            comment: "Weather settings: under the City row")
    }
    static var noCity: String {
        String(localized: "Not chosen", bundle: .module, comment: "Weather settings: the City row when none is set")
    }
    static var cityPrompt: String {
        String(localized: "Type a city", bundle: .module, comment: "Weather settings: the city field's placeholder")
    }
    static var locationTitle: String {
        String(localized: "Use my location", bundle: .module, comment: "Weather settings: the location switch")
    }
    static var locationDetail: String {
        String(
            localized: "Rough location only, and only while the app is open. Your city is used when this is off.",
            bundle: .module, comment: "Weather settings: under the Use my location switch")
    }
    static var blocked: String {
        String(
            localized: "Location is off for this app in Settings, so the weather uses your city.", bundle: .module,
            comment: "Weather settings: when iOS doesn't allow location")
    }
    static var openSettings: String {
        String(localized: "Open Settings", bundle: .module, comment: "Weather settings: opens iOS Settings")
    }
    static var needsPlace: String {
        String(
            localized: "Choose a city or turn on your location to see the weather.", bundle: .module,
            comment: "Weather settings: live weather is on but no place is set")
    }
    static var sample: String {
        String(
            localized:
                "Live weather isn’t switched on in this test build. The weather you see is a sample, and nothing is sent.",
            bundle: .module, comment: "Weather settings: the weather is made up in this build")
    }
    static var removeCity: String {
        String(localized: "Remove my city", bundle: .module, comment: "Weather settings: forgets the city")
    }
    static var searchNote: String {
        String(
            localized: "The name you type goes to Apple Maps to find the city. Only a rough point is kept.",
            bundle: .module, comment: "Weather settings: what searching for a city sends")
    }
    static var searching: String {
        String(localized: "Searching…", bundle: .module, comment: "Weather settings: city search in progress")
    }
    static var noMatch: String {
        String(
            localized: "No city found. Try a larger city nearby.", bundle: .module,
            comment: "Weather settings: city search found nothing")
    }
    static var searchFailed: String {
        String(
            localized: "Can’t search right now. Check your connection.", bundle: .module,
            comment: "Weather settings: city search couldn't run")
    }
    static var explainerTitle: String {
        String(
            localized: "Use the weather where you are?", bundle: .module,
            comment: "Alert title before iOS asks for location")
    }
    static var explainerMessage: String {
        String(
            localized:
                "The app asks Apple Weather for today’s forecast near you. It uses a rough location, not your exact address, and doesn’t keep it. Only the weather itself, like “cool and rainy”, goes into Style Me.",
            bundle: .module, comment: "Alert message before iOS asks for location")
    }
    static var explainerContinue: String {
        String(localized: "Continue", bundle: .module, comment: "Alert button before iOS asks for location")
    }
    static var explainerCity: String {
        String(localized: "Type a city instead", bundle: .module, comment: "Alert button: skip location, use a city")
    }
    static var sheetTitle: String {
        String(localized: "Your city", bundle: .module, comment: "City sheet title")
    }
    static var sheetSubtitle: String {
        String(
            localized: "The weather is for this city.", bundle: .module, comment: "City sheet subtitle")
    }
}
