import CryptoKit
import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Networking

/// Paid actions (Phase 24b) through the real client, App Attest stand-in and fake backend: the
/// idempotency key on every retry, the rate limit, allowances, the kill switch, and what happens
/// when the backend refuses the device's key.
@Suite("Paid actions")
struct PaidActionTests {
    let backend = FakeBackend()
    let auth = FakeAuthProvider(subject: "lily")
    let attester = FakeDeviceAttester()
    let policy = RetryPolicy(requestTimeout: .seconds(60))
    /// The client's clock, which a wait between retries jumps ahead on instead of really waiting,
    /// so these tests neither take real seconds nor have a timeout that a slow machine could hit.
    let clock = ManualClock()

    func client() -> APIClient {
        let clock = clock
        return APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth, policy: policy, clock: clock, sleep: { try await clock.skip($0) })
    }

    func service(attester: (any DeviceAttester)? = nil) async throws -> GatewayPaidActionService {
        let client = client()
        try await auth.signInWithApple()
        _ = try await GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0").whoAmI()
        let session = AttestationSession(
            attester: attester ?? self.attester, store: MemoryAttestKeyStore(), client: client)
        return GatewayPaidActionService(client: client, attestation: session)
    }

    func problem(_ call: () async throws(CloudLimitProblem) -> PaidActionReceipt) async -> CloudLimitProblem? {
        do {
            _ = try await call()
            return nil
        } catch {
            return error
        }
    }

    /// A new quick request (an Ask stylist question) and a new full one on every use, so the
    /// stylist's result cache never answers them (27a).
    static var swap: PaidActionRequest { .style(.sample(.ask, note: String(UUID().uuidString.prefix(8)))) }
    static var full: PaidActionRequest { .style(.sample(.full, note: String(UUID().uuidString.prefix(8)))) }
    static let tryOn = PaidActionRequest.tryOn(contextRevision: "rev_1")

    @Test func aPaidActionRunsOnceAndIsCounted() async throws {
        let paid = try await service()
        let receipt = try await paid.run(Self.full, idempotencyKey: IdempotencyKey.make())
        #expect(!receipt.replayed)
        #expect(receipt.id.hasPrefix("act_"))
        #expect(receipt.usage.category == .styleFull)
        #expect(receipt.usage.usedToday == 1)
        #expect(receipt.usage.remainingToday == 9)
        #expect(backend.paidJobsRun == 1)
        let usage = try await paid.usage()
        #expect(usage.allowance(.styleFull)?.usedToday == 1)
        #expect(usage.paused.isEmpty)
    }

    @Test func aLostAnswerIsRetriedWithTheSameKeyAndNotRunTwice() async throws {
        let paid = try await service()
        // Registers the device's key first, so the lost answer is the paid one.
        _ = try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        // The server does the work, then the answer never arrives: the client times out and
        // retries with the same Idempotency-Key, and gets the first answer back.
        backend.setMode(.answerLost, times: 1)
        let receipt = try await paid.run(Self.full, idempotencyKey: IdempotencyKey.make())
        #expect(receipt.replayed)
        #expect(receipt.usage.usedToday == 1)
        #expect(backend.paidJobsRun == 2)
    }

    @Test func theSameKeyAgainIsAnsweredFromTheRecord() async throws {
        let paid = try await service()
        let key = IdempotencyKey.make()
        let first = try await paid.run(Self.tryOn, idempotencyKey: key)
        let again = try await paid.run(Self.tryOn, idempotencyKey: key)
        #expect(again.id == first.id)
        #expect(again.replayed)
        #expect(again.usage.usedToday == 1)
        #expect(backend.paidJobsRun == 1)
        // The same key for a different request is a bug in the app, and is refused.
        let conflict = await problem { () async throws(CloudLimitProblem) in
            try await paid.run(Self.full, idempotencyKey: key)
        }
        #expect(conflict == .account(.rejected))
    }

    @Test func aBurstIsThrottled() async throws {
        let paid = try await service()
        for _ in 0..<5 { _ = try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make()) }
        let throttled = await problem { () async throws(CloudLimitProblem) in
            try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        }
        guard case .rateLimited(let seconds) = throttled else {
            Issue.record("Expected rateLimited, got \(String(describing: throttled))")
            return
        }
        #expect((1...12).contains(seconds))
        #expect(backend.paidJobsRun == 5)
    }

    @Test(.timeLimit(.minutes(1))) func startingOverAfterAThrottleWorks() async throws {
        let paid = try await service()
        for _ in 0..<5 { _ = try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make()) }
        _ = await problem { () async throws(CloudLimitProblem) in
            try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        }
        backend.resetUsage()
        for _ in 0..<3 { _ = try await paid.run(Self.tryOn, idempotencyKey: IdempotencyKey.make()) }
        #expect(backend.paidJobsRun == 3)
    }

    @Test func aUsedUpAllowanceSaysWhenItComesBack() async throws {
        let paid = try await service()
        let started = Date()
        for _ in 0..<3 { _ = try await paid.run(Self.tryOn, idempotencyKey: IdempotencyKey.make()) }
        let used = await problem { () async throws(CloudLimitProblem) in
            try await paid.run(Self.tryOn, idempotencyKey: IdempotencyKey.make())
        }
        guard case .quotaExceeded(let category, let resetAt) = used else {
            Issue.record("Expected quotaExceeded, got \(String(describing: used))")
            return
        }
        #expect(category == .tryOn)
        #expect(resetAt.timeIntervalSince(started) > 86_000 && resetAt.timeIntervalSince(started) < 86_500)
        #expect(try await paid.usage().allowance(.tryOn)?.remainingToday == 0)
    }

    @Test func theKillSwitchPausesOneFeatureOnly() async throws {
        let paid = try await service()
        backend.setPaused("tryOn", true)
        let paused = await problem { () async throws(CloudLimitProblem) in
            try await paid.run(Self.tryOn, idempotencyKey: IdempotencyKey.make())
        }
        #expect(paused == .paused(feature: .tryOn, retryAfterSeconds: nil))
        #expect(try await paid.usage().paused == [.tryOn])
        _ = try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        backend.setPaused("tryOn", false)
        _ = try await paid.run(Self.tryOn, idempotencyKey: IdempotencyKey.make())
        #expect(backend.paidJobsRun == 2)
    }

    @Test func aRefusedKeyIsRegisteredAgainOnce() async throws {
        let paid = try await service()
        _ = try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        backend.setMode(.attestationRejected, times: 1)
        let receipt = try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        #expect(!receipt.replayed)
        // Refused every time: it gives up after one new key, and says the device isn't verified.
        backend.setMode(.attestationRejected, times: nil)
        let refused = await problem { () async throws(CloudLimitProblem) in
            try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        }
        #expect(refused == .deviceNotVerified)
        #expect(backend.paidJobsRun == 2)
    }

    @Test func aDeviceThatCantAttestGetsNoPaidAccess() async throws {
        let paid = try await service(attester: FakeDeviceAttester(supported: false))
        let refused = await problem { () async throws(CloudLimitProblem) in
            try await paid.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        }
        #expect(refused == .deviceNotVerified)
        #expect(backend.paidJobsRun == 0)
    }

    @Test func withoutAnAssertionTheBackendRefuses() async throws {
        _ = try await service()
        let failure: APIFailure? = await { () async -> APIFailure? in
            do throws(APIFailure) {
                _ = try await client().send(
                    APIV1.style, body: APIV1.StyleRequest(StyleCall.sample(.ask)),
                    idempotencyKey: IdempotencyKey.make(), signer: nil, as: APIV1.StyleResponse.self)
                return nil
            } catch {
                return error
            }
        }()
        #expect(failure == .attestationRequired)
    }

    @Test func signedOutIsSaidPlainly() async {
        let client = client()
        let paid = GatewayPaidActionService(
            client: client,
            attestation: AttestationSession(attester: attester, store: MemoryAttestKeyStore(), client: client))
        do {
            _ = try await paid.usage()
            Issue.record("Expected signed out")
        } catch {
            #expect(error == .account(.signedOut))
        }
    }

    @Test func failuresMapToWhatTheScreenNeeds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let map = { (failure: APIFailure, paid: Bool) in
            GatewayPaidActionService.problem(for: failure, paid: paid, now: now)
        }
        #expect(
            map(.quotaExceeded(category: "styleQuick", resetAt: nil, retryAfterSeconds: 60), true)
                == .quotaExceeded(category: .styleQuick, resetAt: now.addingTimeInterval(60)))
        #expect(
            map(.quotaExceeded(category: "monthlySpend", resetAt: now, retryAfterSeconds: 1), true)
                == .quotaExceeded(category: .monthlySpend, resetAt: now))
        #expect(
            map(.featurePaused(feature: nil, retryAfterSeconds: 30), true)
                == .paused(feature: nil, retryAfterSeconds: 30))
        #expect(map(.actionInProgress(retryAfterSeconds: 60), true) == .busy(retryAfterSeconds: 60))
        #expect(map(.unavailable(retryAfterSeconds: 30), true) == .didNotFinish(retryAfterSeconds: 30))
        #expect(map(.unavailable(retryAfterSeconds: 30), false) == .account(.unavailable(retryAfterSeconds: 30)))
        #expect(map(.offline, true) == .account(.offline))
    }
}

/// The App Attest pieces against the contract and each other.
@Suite("App Attest")
struct AttestationTests {
    @Test func clientDataMatchesTheContractExample() throws {
        let data = try Data(contentsOf: ContractTests.root.appending(path: "v1/examples/attest.client-data.json"))
        let example = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        let clientData = AttestClientData.make(
            method: example["method"]!, path: example["path"]!, idempotencyKey: example["idempotencyKey"]!,
            body: Data(example["body"]!.utf8))
        #expect(clientData == example["clientData"])
        #expect(AttestClientData.hash(clientData).base64EncodedString() == example["clientDataHashBase64"])
        // The app's own encoding of that request gives the same body bytes.
        let call = StyleCall(
            mode: .full, contextRevision: "rev_7f3a9c", consentVersion: "stylist-1", pieces: [], outfit: nil,
            question: nil)
        let encoded = try APIV1.encoder().encode(APIV1.StyleRequest(call))
        #expect(String(decoding: encoded, as: UTF8.self) == example["body"])
    }

    @Test func fakeAssertionsAreShapedLikeApplesAndCountUp() async throws {
        let attester = FakeDeviceAttester()
        let keyID = try await attester.generateKey()
        let attestation = try await attester.attestKey(keyID, clientDataHash: AttestClientData.hash("chl_x"))
        let document = try #require(JSONSerialization.jsonObject(with: attestation) as? [String: String])
        let raw = try #require(Data(base64Encoded: document["publicKey"]!))
        #expect(Data(SHA256.hash(data: raw)).base64EncodedString() == keyID)
        let key = try P256.Signing.PublicKey(x963Representation: raw)

        let hash = AttestClientData.hash("hello")
        for expected in UInt32(1)...3 {
            let assertion = try await attester.generateAssertion(keyID, clientDataHash: hash)
            let map = try #require(MiniCBOR.decodeMap(assertion))
            let authData = try #require(map["authenticatorData"])
            #expect(authData.prefix(32) == Data(SHA256.hash(data: Data(FakeDeviceAttester.appID.utf8))))
            let counter = authData.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            #expect(counter == expected)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: try #require(map["signature"]))
            #expect(key.isValidSignature(signature, for: Data(SHA256.hash(data: authData + hash))))
        }
        await #expect(throws: AttestError.invalidKey) {
            try await attester.generateAssertion("nope", clientDataHash: hash)
        }
    }

    @Test func miniCBORRefusesWhatItDoesntKnow() {
        #expect(MiniCBOR.decodeMap(Data()) == nil)
        #expect(MiniCBOR.decodeMap(Data([0xa1, 0x61, 0x61])) == nil)  // truncated
        #expect(MiniCBOR.decodeMap(Data([0x80])) == nil)  // an array
        let map = MiniCBOR.encodeMap([("a", Data([1, 2, 3]))])
        #expect(MiniCBOR.decodeMap(map) == ["a": Data([1, 2, 3])])
        #expect(MiniCBOR.decodeMap(map + Data([0])) == nil)  // trailing bytes
    }
}
