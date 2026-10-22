import Foundation
import Models
import NookTestSupport
import Testing

@testable import Networking

/// Phase 30c: the app's half of the server's purchase records. The session gives the account's
/// purchase token (which StoreKit purchases then carry), and the subscription or complimentary
/// unlock is claimed through POST /v1/entitlements/claim. The fake backend links a purchase to the
/// first account and refuses another; the real backend also verifies Apple's signature (backend
/// tests/appstore.test.ts).
@Suite("Styling access claims")
struct StylingAccessClaimTests {
    let backend = FakeBackend()

    private func account(_ subject: String, token: PurchaseAccountToken = PurchaseAccountToken()) async throws
        -> (GatewayCreditClaimer, GatewayAccountService)
    {
        let auth = FakeAuthProvider(subject: subject)
        let policy = RetryPolicy(requestTimeout: .seconds(60))
        let client = APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth, policy: policy)
        let service = GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0", purchaseToken: token)
        _ = try await service.signIn()
        return (GatewayCreditClaimer(client: client), service)
    }

    static func jws(_ fields: [String: Any] = [:]) -> String {
        var payload: [String: Any] = [
            "transactionId": "2000000000000101", "originalTransactionId": "2000000000000101",
            "bundleId": "com.jsayram.niftyoutfitnook", "productId": SubscriptionProducts.monthly,
            "type": "Auto-Renewable Subscription",
            "expiresDate": (Date().timeIntervalSince1970 + 30 * 86_400) * 1000,
        ]
        payload.merge(fields) { $1 }
        return CreditClaimTests.jws(payload)
    }

    @Test func signingInHandsTheAccountsPurchaseTokenToStoreKitAndSigningOutTakesItBack() async throws {
        let token = PurchaseAccountToken()
        let (_, service) = try await account("lily", token: token)
        let first = try #require(token.current)
        _ = try await service.whoAmI()
        #expect(token.current == first)
        await service.signOut()
        #expect(token.current == nil)
    }

    @Test func eachAccountHasItsOwnPurchaseToken() async throws {
        let lily = PurchaseAccountToken()
        let other = PurchaseAccountToken()
        _ = try await account("lily", token: lily)
        _ = try await account("other", token: other)
        #expect(lily.current != nil)
        #expect(lily.current != other.current)
    }

    @Test func theSubscriptionAndTheUnlockAreClaimedOnceAndAnotherAccountIsRefused() async throws {
        let (lily, _) = try await account("lily")
        #expect(try await lily.claimStylingAccess(signedTransaction: Self.jws()))
        // Repeating it is safe (every status read at launch sends it again).
        #expect(try await lily.claimStylingAccess(signedTransaction: Self.jws()))
        let unlock = Self.jws([
            "transactionId": "2000000000000102", "originalTransactionId": "2000000000000102",
            "productId": SubscriptionProducts.complimentary, "type": "Non-Consumable",
        ])
        #expect(try await lily.claimStylingAccess(signedTransaction: unlock))
        let (other, _) = try await account("other")
        await #expect(throws: CreditClaimProblem.rejected) {
            try await other.claimStylingAccess(signedTransaction: Self.jws())
        }
        #expect(backend.stylingClaims == 4)
    }

    @Test func anExpiredOrRefundedSubscriptionGivesNoAccessAndPacksArentStylingAccess() async throws {
        let (lily, _) = try await account("lily")
        let expired = Self.jws([
            "transactionId": "2000000000000201", "originalTransactionId": "2000000000000201",
            "expiresDate": (Date().timeIntervalSince1970 - 60) * 1000,
        ])
        #expect(try await lily.claimStylingAccess(signedTransaction: expired) == false)
        let refunded = Self.jws([
            "transactionId": "2000000000000202", "originalTransactionId": "2000000000000202",
            "revocationDate": Date().timeIntervalSince1970 * 1000,
        ])
        #expect(try await lily.claimStylingAccess(signedTransaction: refunded) == false)
        await #expect(throws: CreditClaimProblem.rejected) {
            try await lily.claimStylingAccess(signedTransaction: CreditClaimTests.jws())
        }
    }

    @Test func whenTheServerCantCheckPurchasesTheClaimIsUnavailable() async throws {
        let (lily, _) = try await account("lily")
        backend.setCreditsAvailable(false)
        await #expect(throws: CreditClaimProblem.unavailable) {
            try await lily.claimStylingAccess(signedTransaction: Self.jws())
        }
    }

    @Test func entitlementRequiredIsAForbiddenStatusOlderAppsUnderstand() {
        #expect(APIV1.ErrorCode.entitlementRequired.status == 403)
    }
}
