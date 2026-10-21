import CryptoKit
import Foundation
import Synchronization

// App Attest (Phase 24b, THREAT_MODEL F6). Every paid request carries an assertion from a key
// this install registered with the backend, so a script or a cloned app can't spend her
// allowance or Jose's money. `AppAttestDeviceAttester` uses Apple's DCAppAttestService on a real
// device; `FakeDeviceAttester` stands in on the simulator (which can't attest) and in tests, and
// only the backend's "mock" mode accepts its keys.

/// Why a device couldn't make a key, an attestation or an assertion.
public enum AttestError: Error, Sendable, Equatable {
    /// This device can't attest (the simulator, an older device, or the capability is missing).
    case unsupported
    /// The key is no longer valid (for example after a restore to a new device): make a new one.
    case invalidKey
    /// Anything else, including a temporary failure of Apple's service.
    case failed
}

/// Makes App Attest keys, attestations and assertions. Mirrors DCAppAttestService.
public protocol DeviceAttester: Sendable {
    var isSupported: Bool { get }
    /// A new key in the Secure Enclave. Returns its key ID (base64 of the SHA-256 of the public key).
    func generateKey() async throws(AttestError) -> String
    /// Apple's attestation of the key over `clientDataHash`, for registering it with the backend.
    func attestKey(_ keyID: String, clientDataHash: Data) async throws(AttestError) -> Data
    /// A CBOR assertion over `clientDataHash`, for one request.
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws(AttestError) -> Data
}

/// The contract's client data (contract.json, `attestation.clientData`): what each assertion signs.
public enum AttestClientData {
    public static func make(method: String, path: String, idempotencyKey: String, body: Data) -> String {
        let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return ["nook-assert-v1", method, path, idempotencyKey, bodyHash].joined(separator: "\n")
    }

    public static func hash(_ text: String) -> Data {
        Data(SHA256.hash(data: Data(text.utf8)))
    }
}

/// Just enough CBOR for App Attest assertions: a map of text keys to byte strings.
enum MiniCBOR {
    static func encodeMap(_ entries: [(String, Data)]) -> Data {
        var out = head(major: 5, length: entries.count)
        for (key, value) in entries {
            out += head(major: 3, length: key.utf8.count) + Data(key.utf8)
            out += head(major: 2, length: value.count) + value
        }
        return out
    }

    /// Reads a map of text keys to byte strings, refusing anything else.
    static func decodeMap(_ data: Data) -> [String: Data]? {
        let bytes = [UInt8](data)
        var at = 0
        func length(_ info: UInt8) -> Int? {
            switch info {
            case 0..<24: return Int(info)
            case 24:
                guard at < bytes.count else { return nil }
                defer { at += 1 }
                return Int(bytes[at])
            case 25:
                guard at + 1 < bytes.count else { return nil }
                defer { at += 2 }
                return Int(bytes[at]) << 8 | Int(bytes[at + 1])
            default: return nil
            }
        }
        func item(major expected: UInt8) -> Data? {
            guard at < bytes.count, bytes[at] >> 5 == expected else { return nil }
            let info = bytes[at] & 0x1f
            at += 1
            guard let n = length(info), at + n <= bytes.count else { return nil }
            defer { at += n }
            return Data(bytes[at..<(at + n)])
        }
        guard !bytes.isEmpty, bytes[0] >> 5 == 5 else { return nil }
        let info = bytes[0] & 0x1f
        at = 1
        guard let count = length(info), count <= 8 else { return nil }
        var map: [String: Data] = [:]
        for _ in 0..<count {
            guard let key = item(major: 3).flatMap({ String(data: $0, encoding: .utf8) }), let value = item(major: 2)
            else { return nil }
            map[key] = value
        }
        return at == bytes.count ? map : nil
    }

    private static func head(major: UInt8, length: Int) -> Data {
        switch length {
        case 0..<24: Data([major << 5 | UInt8(length)])
        case 24..<256: Data([major << 5 | 24, UInt8(length)])
        default: Data([major << 5 | 25, UInt8(length >> 8), UInt8(length & 0xff)])
        }
    }
}

/// Where this install keeps its registered key ID, so it registers once, not on every launch.
public protocol AttestKeyStore: Sendable {
    func load() -> String?
    func save(_ keyID: String)
    func clear()
}

/// In memory, for the fakes and tests.
public final class MemoryAttestKeyStore: AttestKeyStore {
    private let value = Mutex<String?>(nil)
    public init() {}
    public func load() -> String? { value.withLock { $0 } }
    public func save(_ keyID: String) { value.withLock { $0 = keyID } }
    public func clear() { value.withLock { $0 = nil } }
}
