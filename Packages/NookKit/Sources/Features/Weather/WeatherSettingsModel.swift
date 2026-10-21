import Foundation
import Models
import Observation

/// What she chose for live weather, and the steps to change it (Phase 29): switch it on, pick a
/// city by name (no permission), or turn on "Use my location" (approximate, While Using).
///
/// "Use my location" asks iOS only after her own tap and the app's own explanation. If iOS
/// doesn't allow it, the switch goes back to off, the city keeps working, and she's told where
/// to change it in Settings. Nothing here ever holds a position.
@MainActor
@Observable
final class WeatherSettingsModel {
    enum Search: Equatable {
        case idle
        case searching
        case results([WeatherPlace])
        /// Nothing matched.
        case none
        /// The search couldn't run: offline.
        case failed
    }

    private(set) var settings = WeatherSettings.off
    private(set) var access = LocationAccess.notDetermined
    private(set) var search = Search.idle
    /// Shows the app's explanation before iOS's own question.
    var showsLocationExplainer = false
    var showsCityPicker = false
    private(set) var credit: WeatherCredit?

    @ObservationIgnored private var services: NookServices?

    var isSample: Bool { services?.usesSampleWeather ?? true }

    /// Her location is wanted but iOS says no: she turned it off in Settings, or said no when asked.
    var locationIsBlocked: Bool { wasRefused && access == .denied }
    private var wasRefused = false

    func load(from services: NookServices) async {
        self.services = services
        settings = services.weatherSettings.current()
        access = await services.location.access()
        // Turned off in iOS Settings after she turned it on here: say so, and keep the city.
        if settings.usesMyLocation, access == .denied {
            wasRefused = true
            settings.usesMyLocation = false
            services.weatherSettings.save(settings)
        }
        credit = settings.isOn ? await services.weather.attribution() : nil
    }

    func setOn(_ isOn: Bool) {
        settings.isOn = isOn
        if !isOn { settings.usesMyLocation = false }
        save()
        Task { credit = isOn ? await services?.weather.attribution() : nil }
    }

    /// The "Use my location" switch. Turning it on shows the explanation first.
    func setUsesMyLocation(_ wanted: Bool) {
        if wanted {
            wasRefused = false
            showsLocationExplainer = true
        } else {
            settings.usesMyLocation = false
            save()
        }
    }

    /// "Continue" in the explanation: iOS asks (if it hasn't), and the switch follows the answer.
    func continueWithLocation() async {
        showsLocationExplainer = false
        guard let services else { return }
        access = await services.location.requestAccess()
        if access == .allowed {
            settings.usesMyLocation = true
            settings.isOn = true
        } else {
            settings.usesMyLocation = false
            wasRefused = true
        }
        save()
    }

    /// "Type a city instead" in the explanation.
    func chooseCityInstead() {
        showsLocationExplainer = false
        showsCityPicker = true
    }

    func choose(_ place: WeatherPlace) {
        settings.city = place
        settings.isOn = true
        save()
        showsCityPicker = false
        search = .idle
    }

    func removeCity() {
        settings.city = nil
        save()
        showsCityPicker = false
        search = .idle
    }

    func find(_ text: String) async {
        guard let services else { return }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            search = .idle
            return
        }
        // Wait for her to stop typing, so each letter isn't a search. A newer search cancels this.
        do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        search = .searching
        do {
            let places = try await services.cities.cities(matching: query)
            search = places.isEmpty ? .none : .results(places)
        } catch {
            if error != .cancelled { search = .failed }
        }
    }

    private func save() {
        services?.weatherSettings.save(settings)
    }
}
