import Models
import SwiftUI
import Testing

@testable import Features

@MainActor
struct ServicesEnvironmentTests {
    /// Until the root sets real services, a screen gets services that fail every call, so it
    /// shows its error state instead of pretending to load or save.
    @Test func screensGetUnavailableServicesUntilTheRootSetsThem() async {
        let services = EnvironmentValues().services
        await #expect(throws: StoreError.unavailable) { try await services.closet.garments() }
        await #expect(throws: StoreError.unavailable) { try await services.profile.update { $0.signName = "Lily" } }
        await #expect(throws: StoreError.unavailable) { try await services.tours.progress() }
        await #expect(throws: WeatherError.unavailable) { try await services.weather.currentWeather() }
        #expect(Set(services.deletion.parts(in: .thisDevice)) == Set(DataPart.allCases.filter { !$0.isRemote }))
        #expect(await services.deletion.delete(.thisDevice).isComplete == false)
    }
}
