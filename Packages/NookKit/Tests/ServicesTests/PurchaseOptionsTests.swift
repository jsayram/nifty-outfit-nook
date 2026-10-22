import Foundation
import StoreKit
import Testing

@testable import Services

/// Phase 30c: every StoreKit purchase carries the account's token from the server, so Apple's
/// server notifications name the account; signed out, purchases carry nothing.
@Suite("Purchase options")
struct PurchaseOptionsTests {
    @Test func aSignedInPurchaseCarriesTheAccountTokenAndNothingElse() throws {
        let token = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000000"))
        #expect(StoreKitSubscriptionService.purchaseOptions(token: token) == [.appAccountToken(token)])
    }

    @Test func aSignedOutPurchaseCarriesNoToken() {
        #expect(StoreKitSubscriptionService.purchaseOptions(token: nil).isEmpty)
    }
}
