import Foundation

// Picture credits (Phase 30b, PRD 14.4): consumable packs of extra try-on pictures, bought with
// StoreKit. The server keeps the balance: after a purchase the app sends the signed transaction to
// POST /v1/credits/claim and finishes the transaction only once the server has credited it, so a
// purchase is never lost between Apple and the server. Credits never expire and still work after
// the subscription ends. Crediting is mocked on the server until 30c checks Apple's signature.

/// The picture packs' App Store product IDs. They must match App Store Connect exactly
/// (`docs/payments.md`) and the server's product list (`convex/credits.ts`).
public enum CreditPacks {
    public static let small = "com.jsayram.niftyoutfitnook.pictures.small"
    public static let large = "com.jsayram.niftyoutfitnook.pictures.large"
    public static let all: Set<String> = [small, large]

    /// PLACEHOLDER sizes until Jose decides (PRD 14.4 leaves them open). The server credits from
    /// its own list; the app uses these only to name a pack.
    public static let pictures: [String: Int] = [small: 10, large: 30]
}

/// One pack as the App Store sells it: the price is the App Store's, never typed in the app.
public struct CreditPackOffer: Sendable, Equatable, Identifiable {
    public var productID: String
    public var displayName: String
    /// The App Store's localized price, like "$2.99".
    public var displayPrice: String
    public var pictures: Int

    public var id: String { productID }

    public init(productID: String, displayName: String, displayPrice: String, pictures: Int) {
        self.productID = productID
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.pictures = pictures
    }
}

/// How buying a pack ended.
public enum CreditPurchaseOutcome: Sendable, Equatable {
    /// Bought, and the server credited it. The pack's pictures and the new balance.
    case credited(pictures: Int, balance: Int)
    /// Bought, but the server hasn't credited it yet (offline, signed out, or the server is busy).
    /// The transaction stays open, so nothing is lost: the app tries again at the next launch and
    /// whenever the store tells it again. Nothing more is charged.
    case awaitingCredit
    /// Waiting on someone else, like Ask to Buy. It's credited when it arrives.
    case pending
    /// She closed Apple's sheet.
    case cancelled
    case failed(SubscriptionProblem)
}

/// What the server said about one claimed purchase.
public struct CreditClaim: Sendable, Equatable {
    public var transactionID: String
    /// The pack's size, from the server's own product list.
    public var pictures: Int
    /// True when this transaction had been credited before: nothing was added this time.
    public var replayed: Bool
    /// Her balance after the claim.
    public var balance: Int

    public init(transactionID: String, pictures: Int, replayed: Bool, balance: Int) {
        self.transactionID = transactionID
        self.pictures = pictures
        self.replayed = replayed
        self.balance = balance
    }
}

/// Why the server didn't credit a purchase. Every one leaves the transaction open, so the app tries
/// again at the next launch; a paid pack is never dropped on the phone.
public enum CreditClaimProblem: Error, Sendable, Equatable {
    case signedOut
    case offline
    case unavailable
    /// The server refused this transaction (not a pack, another app, another account).
    case rejected
    case failed
}

/// Sends a purchase's signed transaction to the server to be credited (POST /v1/credits/claim).
/// The server takes the transaction and product from the JWS, never from the app, and credits each
/// transaction once.
public protocol CreditClaiming: Sendable {
    func claim(signedTransaction: String) async throws(CreditClaimProblem) -> CreditClaim
}

/// Picture packs, as the app sees them. `StoreKitCreditsService` (Services) talks to StoreKit;
/// tests use `ScriptedCreditsService` (Fixtures).
public protocol CreditsService: Sendable {
    /// The packs, from the App Store, smallest first.
    func packs() async throws(SubscriptionProblem) -> [CreditPackOffer]
    /// Buys a pack through Apple's sheet, then has the server credit it.
    func purchase(_ productID: String) async -> CreditPurchaseOutcome
    /// Credits any pack that was paid for but not credited yet (the app closed, or the server
    /// couldn't be reached). Runs at launch. Returns how many were credited now.
    func recoverUnfinished() async -> Int
    /// Her balance each time a purchase is credited, including ones credited in the background
    /// (an approved Ask to Buy, a recovered purchase).
    func balanceUpdates() async -> AsyncStream<Int>
}

/// No store in this build: no packs.
public struct UnavailableCreditsService: CreditsService {
    public init() {}
    public func packs() async throws(SubscriptionProblem) -> [CreditPackOffer] { throw .unavailable }
    public func purchase(_ productID: String) async -> CreditPurchaseOutcome { .failed(.unavailable) }
    public func recoverUnfinished() async -> Int { 0 }
    public func balanceUpdates() async -> AsyncStream<Int> { AsyncStream { $0.finish() } }
}

/// What the next try-on picture would use (PRD 14.4): the month's included pictures first, then
/// purchased credits. Credits work without styling access too, since she paid for them. The server
/// decides for real (30c); this is what the app tells her before she taps.
public enum TryOnFunding: Sendable, Equatable {
    case allowance
    case credit
    case nothing

    /// - Parameters:
    ///   - hasAccess: styling access now.
    ///   - allowanceLeft: pictures left this month, or nil when the app doesn't know (it assumes
    ///     some are left; the server refuses if not).
    ///   - credits: her credit balance, or nil when unknown.
    public static func next(hasAccess: Bool, allowanceLeft: Int?, credits: Int?) -> TryOnFunding {
        if hasAccess, (allowanceLeft ?? 1) > 0 { return .allowance }
        if (credits ?? 0) > 0 { return .credit }
        return .nothing
    }
}

/// No backend in this build: nothing can be credited, so every pack stays unfinished.
public struct UnavailableCreditClaimer: CreditClaiming {
    public init() {}
    public func claim(signedTransaction: String) async throws(CreditClaimProblem) -> CreditClaim {
        throw .unavailable
    }
}
