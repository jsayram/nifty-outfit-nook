import SwiftUI
import Testing

@testable import Features

@MainActor
struct ServicesEnvironmentTests {
    @Test func screensHaveNoServicesUntilTheRootSetsThem() {
        #expect(EnvironmentValues().services == nil)
    }
}
