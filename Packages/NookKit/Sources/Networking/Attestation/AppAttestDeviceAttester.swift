import DeviceCheck
import Foundation
import Security

/// App Attest on a real device, through Apple's DCAppAttestService (DeviceCheck, part of iOS).
///
/// Needs the App Attest capability on the App ID (on since S2, 30 October 2026) and the
/// `com.apple.developer.devicecheck.appattest-environment` entitlement: `development` in Debug
/// builds, `production` in Release (a shipped app always uses production). The backend checks
/// Apple's attestation in its "apple" mode. On the simulator `isSupported` is false, and the app
/// uses `FakeDeviceAttester` with the fake backend instead.
public struct AppAttestDeviceAttester: DeviceAttester {
    public init() {}

    public var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    public func generateKey() async throws(AttestError) -> String {
        guard isSupported else { throw .unsupported }
        do {
            return try await DCAppAttestService.shared.generateKey()
        } catch {
            throw Self.map(error)
        }
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws(AttestError) -> Data {
        do {
            return try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
        } catch {
            throw Self.map(error)
        }
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws(AttestError) -> Data {
        do {
            return try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch {
            throw Self.map(error)
        }
    }

    static func map(_ error: any Error) -> AttestError {
        guard let error = error as? DCError else { return .failed }
        switch error.code {
        case .featureUnsupported: return .unsupported
        case .invalidKey: return .invalidKey
        default: return .failed
        }
    }
}

/// Keeps the registered key ID in the Keychain, on this device only and only while it's unlocked
/// (SECURITY_STANDARD 4). The key ID isn't secret (the private key never leaves the Secure
/// Enclave), but keeping it means one registration per install, as Apple asks.
public struct KeychainAttestKeyStore: AttestKeyStore {
    private let service = "com.jsayram.niftyoutfitnook.appattest"
    private let account = "keyID"

    public init() {}

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ keyID: String) {
        clear()
        var item = query
        item[kSecValueData as String] = Data(keyID.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
