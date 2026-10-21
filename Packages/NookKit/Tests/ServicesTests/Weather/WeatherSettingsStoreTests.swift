import Foundation
import Models
import Testing

@testable import Services

/// Phase 29: her weather choices are kept on the iPhone, hold only a rounded city, and Delete my
/// data empties them.
struct WeatherSettingsStoreTests {
    private func store() -> DefaultsWeatherSettingsStore {
        let name = "test.weather.\(UUID().uuidString)"
        return DefaultsWeatherSettingsStore(suiteName: name)
    }

    @Test func startsOff() {
        #expect(store().current() == .off)
    }

    @Test func keepsWhatSheChose() throws {
        let store = store()
        let city = try #require(
            WeatherPlace(name: "Seattle, WA", coordinate: .init(latitude: 47.61, longitude: -122.33)!))
        let chosen = WeatherSettings(isOn: true, usesMyLocation: true, city: city)
        store.save(chosen)
        #expect(store.current() == chosen)
        #expect(store.current().city?.coordinate == CoarseCoordinate(latitude: 47.6, longitude: -122.3))
    }

    @Test func deleteMyDataEmptiesIt() async throws {
        let store = store()
        store.save(WeatherSettings(isOn: true))
        try await store.eraseAll()
        #expect(store.current() == .off)
    }

    @Test func aDamagedValueReadsAsOff() {
        let name = "test.weather.\(UUID().uuidString)"
        UserDefaults(suiteName: name)?.set(Data("not json".utf8), forKey: DefaultsWeatherSettingsStore.key)
        #expect(DefaultsWeatherSettingsStore(suiteName: name).current() == .off)
    }

    @Test func aStoredPreciseCityIsRoundedWhenRead() {
        let name = "test.weather.\(UUID().uuidString)"
        let json =
            #"{"isOn":true,"usesMyLocation":false,"city":{"name":"Home","coordinate":{"latitude":47.606209,"longitude":-122.332071}}}"#
        UserDefaults(suiteName: name)?.set(Data(json.utf8), forKey: DefaultsWeatherSettingsStore.key)
        let read = DefaultsWeatherSettingsStore(suiteName: name).current()
        #expect(read.city?.coordinate == CoarseCoordinate(latitude: 47.6, longitude: -122.3))
    }
}
