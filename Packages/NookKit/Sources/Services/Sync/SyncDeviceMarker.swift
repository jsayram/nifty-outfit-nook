import Foundation
import Security

/// Tells a restored device from the one that saved the store (0004 §2, "A restored device starts
/// sync fresh"). A random marker sits in the Keychain with `WhenUnlockedThisDeviceOnly`, which never
/// moves to another device, and in sync's ledger, which travels with the store in a device backup.
/// A ledger whose marker the Keychain doesn't hold came from a backup: its engine state and change
/// tags could claim changes were already sent, so they're dropped and sync starts fresh.
public protocol SyncDeviceMarker: Sendable {
    func read() -> String?
    func write(_ marker: String)
}

/// The marker in the Keychain, never synced and never in a backup that restores to another device.
public struct KeychainSyncDeviceMarker: SyncDeviceMarker {
    private let service = "com.jsayram.niftyoutfitnook.icloud-device"
    private let account = "marker"

    public init() {}

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ marker: String) {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(marker.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
