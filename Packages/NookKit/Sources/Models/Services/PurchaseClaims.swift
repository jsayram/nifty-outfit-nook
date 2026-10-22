import Foundation
import Synchronization

// Phase 30c: the server's own record of her purchases. The server verifies Apple's signature on
// every signed transaction it gets and decides styling access from Apple's records alone; the
// app's entitlement hint is never used to authorize anything.

/// Sends the subscription's or the complimentary unlock's signed transaction to the server
/// (POST /v1/entitlements/claim), which links the purchase to this account. Safe to repeat. The
/// answer is whether the server now gives styling access. An offer-code unlock can only reach the
/// server this way: offer codes carry no account token.
public protocol StylingAccessClaiming: Sendable {
    func claimStylingAccess(signedTransaction: String) async throws(CreditClaimProblem) -> Bool
}

extension UnavailableCreditClaimer: StylingAccessClaiming {
    public func claimStylingAccess(signedTransaction: String) async throws(CreditClaimProblem) -> Bool {
        throw .unavailable
    }
}

/// The account token the server gave this account (`user.appAccountToken`), which the app passes
/// to StoreKit with every purchase so Apple's server notifications name the account. A random UUID
/// with nothing personal in it. Nil while signed out, and then purchases carry none.
public final class PurchaseAccountToken: Sendable {
    /// The one the gateway sets on sign-in and StoreKit purchases read.
    public static let shared = PurchaseAccountToken()

    private let value = Mutex<UUID?>(nil)

    public init() {}

    public var current: UUID? { value.withLock { $0 } }

    public func set(_ token: UUID?) {
        value.withLock { $0 = token }
    }
}
