import Foundation
import Models
import NookTestSupport
import Testing

@testable import Networking

/// Phase 30b: picture-credit claims through the real client and the fake backend, as the backend's
/// mocked claim works (convex/credits.ts): the transaction and product come from the JWS, each
/// transaction is credited once, another account can't take it, and GET /v1/usage shows the
/// balance. The StoreKit side is in the app's hosted tests.
@Suite("Picture credits")
struct CreditClaimTests {
    let backend = FakeBackend()

    private func account(_ subject: String) async throws -> (GatewayCreditClaimer, GatewayPaidActionService) {
        let auth = FakeAuthProvider(subject: subject)
        let policy = RetryPolicy(requestTimeout: .seconds(60))
        let client = APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth, policy: policy)
        _ = try await GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0").signIn()
        let attestation = AttestationSession(
            attester: FakeDeviceAttester(), store: MemoryAttestKeyStore(), client: client)
        return (
            GatewayCreditClaimer(client: client), GatewayPaidActionService(client: client, attestation: attestation)
        )
    }

    /// A JWS shaped like StoreKit's, with a stand-in signature (neither fake nor mock checks it; 30c will).
    static func jws(_ fields: [String: Any] = [:]) -> String {
        var payload: [String: Any] = [
            "transactionId": "2000000000000001", "bundleId": "com.jsayram.niftyoutfitnook",
            "productId": CreditPacks.small, "type": "Consumable", "quantity": 1,
        ]
        payload.merge(fields) { $1 }
        func part(_ object: Any) -> String {
            (try? JSONSerialization.data(withJSONObject: object))!.base64EncodedString()
                .replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
        }
        return "\(part(["alg": "ES256"])).\(part(payload)).c2ln"
    }

    @Test func aPackIsCreditedOnceAndUsageShowsTheBalance() async throws {
        let (claimer, paid) = try await account("lily")
        #expect(try await paid.usage().credits == 0)
        let first = try await claimer.claim(signedTransaction: Self.jws())
        #expect(first == CreditClaim(transactionID: "2000000000000001", pictures: 10, replayed: false, balance: 10))
        // The same purchase again (recovery at launch, or the listener and the purchase both).
        let again = try await claimer.claim(signedTransaction: Self.jws())
        #expect(again.replayed)
        #expect(again.balance == 10)
        let large = try await claimer.claim(
            signedTransaction: Self.jws(["transactionId": "2000000000000002", "productId": CreditPacks.large]))
        #expect(large.balance == 40)
        #expect(try await paid.usage().credits == 40)
        #expect(backend.creditedTransactions == 2)
        #expect(backend.creditClaims == 3)
    }

    @Test func anotherAccountCantTakeAPurchase() async throws {
        let (lily, _) = try await account("lily")
        let (other, otherPaid) = try await account("other")
        _ = try await lily.claim(signedTransaction: Self.jws())
        await #expect(throws: CreditClaimProblem.rejected) { try await other.claim(signedTransaction: Self.jws()) }
        #expect(try await otherPaid.usage().credits == 0)
    }

    @Test func onlyThisAppsPacksCountAndTheSizeIsTheServers() async throws {
        let (claimer, _) = try await account("lily")
        for bad in [
            Self.jws(["productId": SubscriptionProducts.monthly, "type": "Auto-Renewable Subscription"]),
            Self.jws(["bundleId": "com.example.other"]), Self.jws(["revocationDate": 1]), "abc.def.ghi",
        ] {
            await #expect(throws: CreditClaimProblem.rejected) { try await claimer.claim(signedTransaction: bad) }
        }
        #expect(try await claimer.claim(signedTransaction: Self.jws(["quantity": 50])).pictures == 10)
    }

    @Test func whileCreditingIsOffNothingIsCreditedAndTheAppKeepsTheTransaction() async throws {
        let (claimer, _) = try await account("lily")
        backend.setCreditsAvailable(false)
        await #expect(throws: CreditClaimProblem.unavailable) { try await claimer.claim(signedTransaction: Self.jws()) }
        #expect(backend.creditBalance(subject: "lily") == 0)
        backend.setCreditsAvailable(true)
        #expect(try await claimer.claim(signedTransaction: Self.jws()).balance == 10)
    }

    @Test func problemsMapToWhatTheAppDoes() {
        #expect(GatewayCreditClaimer.problem(for: .offline) == .offline)
        #expect(GatewayCreditClaimer.problem(for: .signedOut) == .signedOut)
        #expect(GatewayCreditClaimer.problem(for: .forbidden) == .rejected)
        #expect(GatewayCreditClaimer.problem(for: .unavailable(retryAfterSeconds: 60)) == .unavailable)
        #expect(GatewayCreditClaimer.problem(for: .serverError) == .failed)
    }
}
