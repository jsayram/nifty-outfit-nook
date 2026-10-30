import Foundation
import Security
import Testing

@testable import BetterAuth

/// BA4: the Better Auth session's Keychain item (SECURITY_STANDARD 4): this device only, only while
/// unlocked, never synced. Here and not in the package tests because the Keychain needs a host app
/// with its entitlements; a package test bundle on the simulator gets `errSecMissingEntitlement`.
/// Uses an item of its own, never the app's.
@Suite("Session in the Keychain")
struct KeychainSessionStoreTests {
    let store = KeychainSessionStore(service: "com.jsayram.niftyoutfitnook.session.tests." + UUID().uuidString.prefix(8))

    @Test func theItemIsThisDeviceOnlyWhenUnlockedAndNeverSynced() throws {
        defer { store.clear() }
        #expect(store.save("session-value-for-the-test-only"))
        #expect(store.load() == "session-value-for-the-test-only")
        let attributes = try #require(store.attributes())
        #expect(
            attributes[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect((attributes[kSecAttrSynchronizable as String] as? Bool ?? false) == false)
        #expect(attributes[kSecValueData as String] == nil)
    }

    @Test func savingReplacesAndClearingRemoves() {
        defer { store.clear() }
        store.save("first-session-value-0000")
        store.save("second-session-value-000")
        #expect(store.load() == "second-session-value-000")
        store.clear()
        #expect(store.load() == nil)
        #expect(store.attributes() == nil)
    }
}
