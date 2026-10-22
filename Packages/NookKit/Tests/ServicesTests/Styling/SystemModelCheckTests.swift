import FoundationModels
import Models
import Testing

@testable import Services

/// Phase 28: Foundation Models' availability, as the router reads it.
struct SystemModelCheckTests {
    @Test func everyAvailabilityMapsToAStatus() {
        #expect(SystemModelCheck.status(for: .available) == .available)
        #expect(SystemModelCheck.status(for: .unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(
            SystemModelCheck.status(for: .unavailable(.appleIntelligenceNotEnabled)) == .appleIntelligenceNotEnabled)
        #expect(SystemModelCheck.status(for: .unavailable(.modelNotReady)) == .modelNotReady)
    }

    /// The real check answers on any device, simulator included, without throwing.
    @Test func theRealCheckAnswers() {
        _ = SystemModelCheck().status()
    }
}
