import Foundation

// Cloud work that costs money (Phase 24b): what is left of her allowances, the limits the server
// enforces, and asking for a paid action. Her closet never depends on any of this. The stylist
// (27a) and try-on (33a) call `PaidActionService`; until then only the debug limits screen does.

/// A paid feature the server can switch off on its own.
public enum PaidFeature: String, Sendable, CaseIterable {
    case style
    case tryOn
}

/// What an allowance counts. `monthlySpend` is the account's overall monthly limit, which isn't a
/// count she sees, only a reason something stopped.
public enum UsageCategory: String, Sendable, CaseIterable {
    case styleFull
    case styleQuick
    case tryOn
    case monthlySpend
}

/// One allowance: how much she used today and in the last 30 days, and when the next one frees up.
public struct UsageAllowance: Sendable, Equatable {
    public var category: UsageCategory
    public var usedToday: Int
    public var limitToday: Int
    public var usedThisMonth: Int
    public var limitThisMonth: Int
    /// When the oldest counted use stops counting. Nil when nothing counts.
    public var resetsAt: Date?

    public init(
        category: UsageCategory, usedToday: Int, limitToday: Int, usedThisMonth: Int, limitThisMonth: Int,
        resetsAt: Date?
    ) {
        self.category = category
        self.usedToday = usedToday
        self.limitToday = limitToday
        self.usedThisMonth = usedThisMonth
        self.limitThisMonth = limitThisMonth
        self.resetsAt = resetsAt
    }

    /// What she can still do today: the smaller of what is left today and this month.
    public var remainingToday: Int {
        max(0, min(limitToday - usedToday, limitThisMonth - usedThisMonth))
    }
}

/// Her allowances and which paid features are on, as the server reports them.
public struct CloudUsage: Sendable, Equatable {
    public var allowances: [UsageAllowance]
    public var paused: Set<PaidFeature>

    public init(allowances: [UsageAllowance], paused: Set<PaidFeature>) {
        self.allowances = allowances
        self.paused = paused
    }

    public func allowance(_ category: UsageCategory) -> UsageAllowance? {
        allowances.first { $0.category == category }
    }
}

/// A paid action to ask for. Try-on is a placeholder until 33a gives it its real inputs.
public enum PaidActionRequest: Sendable, Equatable {
    /// 27a: the cloud stylist (an outfit, or an Ask stylist question).
    case style(StyleCall)
    /// `contextRevision` names the version of what's being drawn, never its content.
    case tryOn(contextRevision: String)

    public var feature: PaidFeature {
        switch self {
        case .style: .style
        case .tryOn: .tryOn
        }
    }

    public var category: UsageCategory {
        switch self {
        case .style(let call): call.mode == .full ? .styleFull : .styleQuick
        case .tryOn: .tryOn
        }
    }
}

/// What came back from a paid action.
public struct PaidActionReceipt: Sendable, Equatable {
    public var id: String
    public var feature: PaidFeature
    /// True when this was a retry the server had already done: it wasn't run or counted again.
    public var replayed: Bool
    public var usage: UsageAllowance
    /// 27a: the stylist's checked answer. `nil` for try-on.
    public var style: StyleAnswer?

    public init(id: String, feature: PaidFeature, replayed: Bool, usage: UsageAllowance, style: StyleAnswer? = nil) {
        self.id = id
        self.feature = feature
        self.replayed = replayed
        self.usage = usage
        self.style = style
    }
}

/// Why a paid action, or reading usage, didn't happen, in the terms a screen needs.
public enum CloudLimitProblem: Error, Sendable, Hashable {
    /// Too many in a short time. Try again after this many seconds.
    case rateLimited(retryAfterSeconds: Int)
    /// An allowance is used up until `resetAt`.
    case quotaExceeded(category: UsageCategory, resetAt: Date)
    /// Switched off on the server, or its spending ceiling is reached. Everything else works.
    case paused(feature: PaidFeature?, retryAfterSeconds: Int?)
    /// The same action, or another paid one, is still running or being checked.
    case busy(retryAfterSeconds: Int)
    /// This device can't prove it's the real app (a simulator, or App Attest unavailable).
    case deviceNotVerified
    /// It didn't finish this time (the job failed, or its outcome is still being checked). Trying
    /// again with the same key is safe: it is never run or counted twice.
    case didNotFinish(retryAfterSeconds: Int?)
    /// Signing in, the connection or the server.
    case account(AccountProblem)
    /// 27a: her consent doesn't cover where the server would send this. Nothing was sent.
    case needsConsent
}

/// Paid cloud work through the gateway (24b). The same idempotency key must be passed for every
/// retry of one action, so a retry is never run or counted twice; a new action needs a new key.
public protocol PaidActionService: Sendable {
    func usage() async throws(CloudLimitProblem) -> CloudUsage
    func run(_ request: PaidActionRequest, idempotencyKey: String) async throws(CloudLimitProblem) -> PaidActionReceipt
}

public enum IdempotencyKey {
    /// A new key for a new action: "idem_" and 32 random hex digits.
    public static func make() -> String {
        "idem_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

/// No paid service: everything says signed out.
public struct UnavailablePaidActionService: PaidActionService {
    public init() {}
    public func usage() async throws(CloudLimitProblem) -> CloudUsage { throw .account(.signedOut) }
    public func run(_ request: PaidActionRequest, idempotencyKey: String) async throws(CloudLimitProblem)
        -> PaidActionReceipt
    { throw .account(.signedOut) }
}
