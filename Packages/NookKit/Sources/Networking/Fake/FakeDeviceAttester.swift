import CryptoKit
import Foundation
import Synchronization

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    /// A stand-in for App Attest, for the simulator and tests: P-256 keys from CryptoKit kept in
    /// memory, a stand-in attestation only the backend's "mock" mode (and the fake backend) accept,
    /// and assertions built exactly like Apple's: CBOR {signature, authenticatorData}, a DER ECDSA
    /// signature over SHA-256(authenticatorData || clientDataHash), and a counter that goes up.
    public final class FakeDeviceAttester: DeviceAttester {
        /// The App ID the backend's mock mode expects ("<team ID>.<bundle ID>").
        public static let appID = "MOCKTEAM01.com.jsayram.niftyoutfitnook"

        private struct Key {
            var signer: P256.Signing.PrivateKey
            var counter: UInt32 = 0
        }

        private let keys = Mutex<[String: Key]>([:])
        private let supported: Bool
        private let appID: String

        public init(supported: Bool = true, appID: String = FakeDeviceAttester.appID) {
            self.supported = supported
            self.appID = appID
        }

        public var isSupported: Bool { supported }

        public func generateKey() async throws(AttestError) -> String {
            guard supported else { throw .unsupported }
            let signer = P256.Signing.PrivateKey()
            let keyID = Data(SHA256.hash(data: signer.publicKey.x963Representation)).base64EncodedString()
            keys.withLock { $0[keyID] = Key(signer: signer) }
            return keyID
        }

        public func attestKey(_ keyID: String, clientDataHash: Data) async throws(AttestError) -> Data {
            guard let key = keys.withLock({ $0[keyID] }) else { throw .invalidKey }
            let document: [String: String] = [
                "fmt": "nook-mock-v1",
                "publicKey": key.signer.publicKey.x963Representation.base64EncodedString(),
                "clientDataHash": clientDataHash.base64EncodedString(),
                "appId": appID,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]) else {
                throw .failed
            }
            return data
        }

        public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws(AttestError) -> Data {
            let next: Key? = keys.withLock { keys in
                guard var key = keys[keyID] else { return nil }
                key.counter += 1
                keys[keyID] = key
                return key
            }
            guard let key = next else { throw .invalidKey }
            var authenticatorData = Data(SHA256.hash(data: Data(appID.utf8)))
            authenticatorData.append(0)  // flags
            withUnsafeBytes(of: key.counter.bigEndian) { authenticatorData.append(contentsOf: $0) }
            let nonce = Data(SHA256.hash(data: authenticatorData + clientDataHash))
            guard let signature = try? key.signer.signature(for: nonce) else { throw .failed }
            return MiniCBOR.encodeMap([
                ("signature", signature.derRepresentation), ("authenticatorData", authenticatorData),
            ])
        }

        /// Forgets every key, like a reinstall: the next request registers a new one.
        public func forgetKeys() {
            keys.withLock { $0.removeAll() }
        }
    }
#endif
