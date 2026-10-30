import Foundation
import Security
import Synchronization

/// Where the Better Auth session lives between launches: the one secret the app holds.
public protocol SessionStore: Sendable {
    func load() -> String?
    /// Replaces any session already kept. False when it couldn't be kept.
    @discardableResult func save(_ session: String) -> Bool
    func clear()
}

/// The session in the Keychain (SECURITY_STANDARD 4): one generic-password item, readable only
/// while the phone is unlocked and only on this device (`WhenUnlockedThisDeviceOnly`), never
/// synced to iCloud Keychain and so never in a backup that leaves the phone. Never `UserDefaults`,
/// never logged.
public struct KeychainSessionStore: SessionStore {
    public static let defaultService = "com.jsayram.niftyoutfitnook.session"
    let service: String
    let account = "betterAuth"

    /// - Parameter service: the item's service name. Tests pass their own, so they never touch
    ///   the app's item.
    public init(service: String = KeychainSessionStore.defaultService) {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Only items that don't sync: an item synced by mistake is never read, or matched.
            kSecAttrSynchronizable as String: false,
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

    @discardableResult
    public func save(_ session: String) -> Bool {
        clear()
        var item = query
        item[kSecValueData as String] = Data(session.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }

    /// The kept item's attributes, without its value, for the test that checks its class.
    func attributes() -> [String: Any]? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnAttributes as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? [String: Any]
    }
}

/// A session kept in memory only: a relaunch starts signed out. For the Debug fakes, whose
/// backend forgets its sessions on relaunch too, and for tests.
public final class MemorySessionStore: SessionStore {
    private let session = Mutex<String?>(nil)

    public init() {}

    public func load() -> String? { session.withLock { $0 } }

    @discardableResult
    public func save(_ session: String) -> Bool {
        self.session.withLock { $0 = session }
        return true
    }

    public func clear() { session.withLock { $0 = nil } }
}
