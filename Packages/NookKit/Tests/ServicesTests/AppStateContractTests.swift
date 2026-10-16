import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// The store contracts (`NookTestSupport`) run against the app state kept in `UserDefaults`
/// (Phase 17), each check on a suite of its own.
struct AppStateContractTests {
    @Test(arguments: TourProgressStoreContract.Check.allCases)
    func tours(_ check: TourProgressStoreContract.Check) async throws {
        let suite = AppStateDefaultsTests.Suite()
        try await TourProgressStoreContract { DefaultsTourProgressStore(suiteName: suite.name) }.run(check)
    }

    @Test(arguments: OnboardingStateStoreContract.Check.allCases)
    func onboarding(_ check: OnboardingStateStoreContract.Check) async throws {
        let suite = AppStateDefaultsTests.Suite()
        try await OnboardingStateStoreContract { DefaultsOnboardingStore(suiteName: suite.name) }.run(check)
    }
}
