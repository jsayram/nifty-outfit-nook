import Foundation

/// This install's App Attest key with the backend (24b): registers it the first time a paid request
/// needs it (a one-time challenge, Apple's attestation over it, POST /v1/attest/key), then signs
/// every paid request with a fresh assertion. Never logs a key or an assertion.
public actor AttestationSession: RequestSigner {
    private let attester: any DeviceAttester
    private let store: any AttestKeyStore
    private let client: APIClient
    private var registering: Task<String, any Error>?

    public init(attester: any DeviceAttester, store: any AttestKeyStore, client: APIClient) {
        self.attester = attester
        self.store = store
        self.client = client
    }

    public func headers(for endpoint: APIV1.Endpoint, idempotencyKey: String, body: Data) async throws(APIFailure)
        -> [String: String]
    {
        let keyID = try await registeredKey()
        let clientData = AttestClientData.make(
            method: endpoint.method, path: endpoint.path, idempotencyKey: idempotencyKey, body: body)
        do {
            let assertion = try await attester.generateAssertion(
                keyID, clientDataHash: AttestClientData.hash(clientData))
            return ["X-Nook-Attest-Key": keyID, "X-Nook-Assertion": assertion.base64EncodedString()]
        } catch .unsupported, .temporary {
            // The device can't attest, or Apple's service is busy: the key may still be good.
            throw .attestationUnavailable
        } catch {
            // The stored key can't sign. After a restore to another device that's `invalidKey`; after
            // the app was deleted and installed again, the key ID survives in the Keychain but the
            // key is gone, and iOS 27 answers `invalidInput` (com.apple.devicecheck.error 2; S2,
            // iPhone 14 Pro). Either way, forget it: the caller registers a new key and tries once
            // more, once.
            store.clear()
            throw .attestationRequired
        }
    }

    /// Forgets the registered key, after the backend refused it: the next request registers anew.
    public func reset() {
        store.clear()
    }

    private func registeredKey() async throws(APIFailure) -> String {
        if let keyID = store.load() { return keyID }
        // Two paid requests at once register one key between them.
        let task =
            registering
            ?? Task { [attester, client, store] in
                let keyID = try await Self.register(attester: attester, client: client)
                store.save(keyID)
                return keyID
            }
        registering = task
        defer { registering = nil }
        do {
            return try await task.value
        } catch let failure as APIFailure {
            throw failure
        } catch {
            throw .attestationUnavailable
        }
    }

    private static func register(attester: any DeviceAttester, client: APIClient) async throws(APIFailure) -> String {
        guard attester.isSupported else { throw .attestationUnavailable }
        let keyID: String
        do {
            keyID = try await attester.generateKey()
        } catch {
            throw .attestationUnavailable
        }
        let challenge = try await client.send(APIV1.attestChallenge, as: APIV1.AttestChallenge.self)
        let attestation: Data
        do {
            attestation = try await attester.attestKey(
                keyID, clientDataHash: AttestClientData.hash(challenge.challenge))
        } catch {
            throw .attestationUnavailable
        }
        let request = APIV1.AttestKeyRequest(
            keyId: keyID, attestation: attestation.base64EncodedString(), challenge: challenge.challenge)
        _ = try await client.send(APIV1.attestKey, body: request, as: APIV1.AttestKeyResponse.self)
        return keyID
    }
}
