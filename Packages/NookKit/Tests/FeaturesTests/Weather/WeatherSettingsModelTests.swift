import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Phase 29: the steps in the weather settings, with a scripted permission. A city needs none;
/// her location is asked about only after her own tap and the app's explanation; a no puts the
/// switch back and keeps the city.
@MainActor
struct WeatherSettingsModelTests {
    private static let seattle = WeatherPlace(name: "Seattle, WA", coordinate: .init(latitude: 47.6, longitude: -122.3)!)!

    private func load(location: FixtureLocationProvider, saved: WeatherSettings = .off) async -> (WeatherSettingsModel, NookServices) {
        var services = FixtureServices.make(FixtureConfiguration(set: .demo))
        services.weatherSettings = InMemoryWeatherSettingsStore(saved)
        services.location = location
        services.cities = FixtureCityFinder()
        let model = WeatherSettingsModel()
        await model.load(from: services)
        return (model, services)
    }

    @Test func startsOffAndKeepsNothingUntilAsked() async {
        let (model, services) = await load(location: FixtureLocationProvider(access: .notDetermined))
        #expect(model.settings == .off)
        #expect(services.weatherSettings.current() == .off)
    }

    @Test func aCityTurnsWeatherOnAndNeedsNoPermission() async {
        let location = FixtureLocationProvider(access: .notDetermined)
        let (model, services) = await load(location: location)
        model.choose(Self.seattle)
        #expect(model.settings.isOn && model.settings.city == Self.seattle)
        #expect(services.weatherSettings.current().city == Self.seattle)
        #expect(await location.access() == .notDetermined)
    }

    @Test func theLocationSwitchExplainsFirstAndAsksOnlyAfterContinue() async {
        let location = FixtureLocationProvider(access: .notDetermined, grantsWhenAsked: true)
        let (model, _) = await load(location: location)
        model.setOn(true)
        model.setUsesMyLocation(true)
        #expect(model.showsLocationExplainer)
        #expect(!model.settings.usesMyLocation)
        #expect(await location.access() == .notDetermined)
        await model.continueWithLocation()
        #expect(model.settings.usesMyLocation && !model.showsLocationExplainer && !model.locationIsBlocked)
    }

    @Test func sayingNoPutsTheSwitchBackAndKeepsTheCity() async {
        let (model, services) = await load(location: FixtureLocationProvider(access: .notDetermined, grantsWhenAsked: false))
        model.choose(Self.seattle)
        model.setUsesMyLocation(true)
        await model.continueWithLocation()
        #expect(!model.settings.usesMyLocation && model.settings.isOn)
        #expect(model.locationIsBlocked)
        #expect(model.settings.city == Self.seattle)
        #expect(!services.weatherSettings.current().usesMyLocation)
    }

    @Test func typeACityInsteadAsksNothing() async {
        let location = FixtureLocationProvider(access: .notDetermined)
        let (model, _) = await load(location: location)
        model.setUsesMyLocation(true)
        model.chooseCityInstead()
        #expect(!model.showsLocationExplainer && model.showsCityPicker)
        #expect(await location.access() == .notDetermined)
    }

    @Test func locationTurnedOffInSettingsFallsBackAndSays() async {
        let saved = WeatherSettings(isOn: true, usesMyLocation: true, city: Self.seattle)
        let (model, services) = await load(location: FixtureLocationProvider(access: .denied), saved: saved)
        #expect(!model.settings.usesMyLocation && model.locationIsBlocked)
        #expect(model.settings.city == Self.seattle)
        #expect(!services.weatherSettings.current().usesMyLocation)
    }

    @Test func turningWeatherOffAlsoTurnsLocationOff() async {
        let saved = WeatherSettings(isOn: true, usesMyLocation: true, city: Self.seattle)
        let (model, services) = await load(location: FixtureLocationProvider(access: .allowed), saved: saved)
        model.setOn(false)
        #expect(services.weatherSettings.current() == WeatherSettings(isOn: false, usesMyLocation: false, city: Self.seattle))
    }

    @Test func citySearchFindsMatchesAndSaysWhenNone() async {
        let (model, _) = await load(location: FixtureLocationProvider(access: .denied))
        await model.find("chi")
        #expect(model.search == .results([FixtureCityFinder.known[2]]))
        await model.find("zzzz")
        #expect(model.search == .none)
        await model.find("a")
        #expect(model.search == .idle)
    }

    @Test func offlineSearchSaysSo() async {
        var services = FixtureServices.make(FixtureConfiguration(set: .demo))
        services.cities = FixtureCityFinder(isOffline: true)
        let model = WeatherSettingsModel()
        await model.load(from: services)
        await model.find("sea")
        #expect(model.search == .failed)
    }

    @Test func removingTheCityKeepsTheSwitch() async {
        let saved = WeatherSettings(isOn: true, city: Self.seattle)
        let (model, _) = await load(location: FixtureLocationProvider(access: .denied), saved: saved)
        model.removeCity()
        #expect(model.settings.city == nil && model.settings.isOn)
    }

    @Test func deleteMyDataEmptiesTheChoices() async {
        let saved = WeatherSettings(isOn: true, city: Self.seattle)
        let (_, services) = await load(location: FixtureLocationProvider(access: .denied), saved: saved)
        let report = await services.deletion.delete(.thisDevice)
        #expect(report.isComplete)
        #expect(services.weatherSettings.current() == .off)
    }
}
