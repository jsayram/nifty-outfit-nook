import Foundation
import Synchronization

// The styling subscription (Phase 30a): one monthly auto-renewable subscription with a free month
// for new subscribers (PRD 14.1). The app reads what StoreKit says and shows it; the server is the
// authority for paid work (30c). Her closet never depends on any of this.

/// The App Store products the app sells. The IDs must match App Store Connect exactly
/// (`docs/payments.md`); the local StoreKit configuration file uses the same ones.
public enum SubscriptionProducts {
    /// The one subscription group. Its App Store Connect ID goes to `manageSubscriptionsSheet`.
    public static let groupName = "Styling"
    /// The monthly styling subscription.
    public static let monthly = "com.jsayram.niftyoutfitnook.styling.monthly"
    /// 30b: the complimentary unlock (PRD 14.2): a non-consumable that gives styling access with
    /// no end and no renewal. Never sold in the app; Jose gives it with free one-time App Store
    /// offer codes, which she redeems in Styling access.
    public static let complimentary = "com.jsayram.niftyoutfitnook.styling.complimentary"
    /// Every product that gives styling access.
    public static let all: Set<String> = [monthly, complimentary]
}

/// Where her styling subscription stands, in the words the app uses. StoreKit's own states, with
/// the free month told apart from a paid period.
public enum SubscriptionState: String, Sendable, Codable, CaseIterable {
    /// Never subscribed, or nothing StoreKit could verify.
    case none
    /// In the free month.
    case trial
    /// A paid period.
    case active
    /// A renewal payment failed, and Apple's billing grace period keeps her access for now.
    case gracePeriod
    /// A renewal payment failed and Apple is still trying, without a grace period: no access.
    case billingRetry
    /// The subscription ended.
    case expired
    /// Apple took it back (a refund, or Family Sharing ended).
    case revoked
}

/// Her subscription as StoreKit last reported it.
public struct SubscriptionStatus: Sendable, Equatable, Codable {
    public var state: SubscriptionState
    public var productID: String?
    /// The end of the current period: the free month's last moment, or the next renewal.
    public var expiresAt: Date?
    /// While in a billing grace period, when it ends.
    public var gracePeriodEndsAt: Date?
    /// Whether it renews at the end of the period. False once she cancels.
    public var willAutoRenew: Bool
    /// When StoreKit was read. A cached status is never stretched past its own dates.
    public var checkedAt: Date
    /// 30b: when she redeemed the complimentary unlock, if she has it (and Apple hasn't taken it
    /// back). It gives styling access with no end, alongside whatever the subscription says.
    public var complimentarySince: Date?

    public init(
        state: SubscriptionState, productID: String? = nil, expiresAt: Date? = nil, gracePeriodEndsAt: Date? = nil,
        willAutoRenew: Bool = false, checkedAt: Date, complimentarySince: Date? = nil
    ) {
        self.state = state
        self.productID = productID
        self.expiresAt = expiresAt
        self.gracePeriodEndsAt = gracePeriodEndsAt
        self.willAutoRenew = willAutoRenew
        self.checkedAt = checkedAt
        self.complimentarySince = complimentarySince
    }

    /// Nothing bought, read at `date`.
    public static func none(at date: Date) -> SubscriptionStatus {
        SubscriptionStatus(state: .none, checkedAt: date)
    }

    /// Whether styling access is on at `now`. PRD 14.3: a verified active subscription, including
    /// Apple's grace period. A period that has ended gives nothing, even if StoreKit hasn't been
    /// read since: the status is only as good as the dates Apple gave, so stale data never grants
    /// more than they say. Billing retry without a grace period, expired and revoked give nothing.
    public func hasStylingAccess(at now: Date) -> Bool {
        // 30b: the complimentary unlock has no end date. Apple taking it back removes it.
        if isComplimentary { return true }
        switch state {
        case .trial, .active:
            guard let expiresAt else { return false }
            return now < expiresAt
        case .gracePeriod:
            guard let end = gracePeriodEndsAt ?? expiresAt else { return false }
            return now < end
        case .none, .billingRetry, .expired, .revoked:
            return false
        }
    }

    /// 30b: whether she has the complimentary unlock.
    public var isComplimentary: Bool { complimentarySince != nil }

    /// Whether there's a subscription that may still bill her: what Delete my account warns
    /// about (24c). Billing retry counts, since Apple is still trying to charge.
    public var mayRenew: Bool {
        switch state {
        case .trial, .active, .gracePeriod, .billingRetry: true
        case .none, .expired, .revoked: false
        }
    }

    /// The state as she has it at `now`: a cached trial or paid period whose date has passed
    /// reads as expired until StoreKit says otherwise.
    public func effectiveState(at now: Date) -> SubscriptionState {
        switch state {
        case .trial, .active, .gracePeriod:
            hasStylingAccess(at: now) ? state : .expired
        case .none, .billingRetry, .expired, .revoked:
            state
        }
    }

    /// The non-authoritative hint the app sends with paid requests (30a). The server decides from
    /// Apple's own records (30c) and never trusts this.
    public func hint(at now: Date) -> EntitlementHint {
        isComplimentary ? .complimentary : EntitlementHint(effectiveState(at: now))
    }
}

/// What the app tells the server about her subscription, as a hint only (`X-Nook-Entitlement-Hint`
/// on paid requests). The server's own check (30c) is what counts.
public enum EntitlementHint: String, Sendable, Equatable, CaseIterable {
    case none
    case trial
    case active
    case grace
    case billingRetry = "billing-retry"
    case expired
    case revoked
    /// 30b: the complimentary unlock.
    case complimentary

    public init(_ state: SubscriptionState) {
        switch state {
        case .none: self = .none
        case .trial: self = .trial
        case .active: self = .active
        case .gracePeriod: self = .grace
        case .billingRetry: self = .billingRetry
        case .expired: self = .expired
        case .revoked: self = .revoked
        }
    }
}

/// A length of time in StoreKit's terms ("1 month").
public struct SubscriptionPeriod: Sendable, Equatable, Codable {
    public enum Unit: String, Sendable, Codable {
        case day
        case week
        case month
        case year
    }

    public var unit: Unit
    public var value: Int

    public init(_ value: Int, _ unit: Unit) {
        self.unit = unit
        self.value = value
    }

    /// The date this long after `date`, on the calendar (a month is a calendar month, not 30
    /// days, as Apple counts it).
    public func end(from date: Date, calendar: Calendar) -> Date {
        let component: Calendar.Component =
            switch unit {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }
}

/// What the paywall shows, all from StoreKit: the localized price as the App Store formats it,
/// the period, and the free month only when she can still have it.
public struct SubscriptionOffer: Sendable, Equatable {
    public var productID: String
    public var displayName: String
    /// The App Store's localized price, like "$9.99". Never typed into the app.
    public var displayPrice: String
    public var period: SubscriptionPeriod
    /// The free trial, if this Apple Account can still have it. Nil once it's been used.
    public var freeTrial: SubscriptionPeriod?

    public init(
        productID: String, displayName: String, displayPrice: String, period: SubscriptionPeriod,
        freeTrial: SubscriptionPeriod?
    ) {
        self.productID = productID
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.period = period
        self.freeTrial = freeTrial
    }

    /// When the first charge would be if she started today: after the free month, or today.
    public func firstCharge(startingAt now: Date, calendar: Calendar) -> Date {
        freeTrial?.end(from: now, calendar: calendar) ?? now
    }
}

/// How a purchase ended.
public enum PurchaseOutcome: Sendable, Equatable {
    /// Bought and verified. The new status.
    case purchased(SubscriptionStatus)
    /// Waiting on someone else, like Ask to Buy. It arrives later through `statusUpdates`.
    case pending
    /// She closed Apple's sheet.
    case cancelled
    /// Didn't work. Nothing was charged that the app knows of.
    case failed(SubscriptionProblem)
}

/// Why the store couldn't do something.
public enum SubscriptionProblem: Error, Sendable, Equatable {
    /// The App Store couldn't be reached.
    case offline
    /// Purchases are turned off on this iPhone (Screen Time).
    case notAllowed
    /// The product isn't available here, or the store isn't set up in this build.
    case unavailable
    /// StoreKit couldn't verify what Apple sent. Nothing is granted.
    case unverified
    /// Anything else.
    case failed
}

/// The styling subscription, as the app sees it. `StoreKitSubscriptionService` (Services) talks
/// to StoreKit 2; tests and debug launches use `ScriptedSubscriptionService` (Fixtures).
public protocol SubscriptionService: Sendable {
    /// The subscription group's ID, for Apple's Manage subscription sheet. Nil when the store
    /// can't say (no store in this build, or the product didn't load).
    func subscriptionGroupID() async -> String?
    /// The last known status, from the cache if StoreKit hasn't been read yet. Never blocks on
    /// the network.
    func cachedStatus() async -> SubscriptionStatus
    /// Reads StoreKit again (its own on-device records, which work offline) and caches the result.
    func refresh() async -> SubscriptionStatus
    /// Each new status after a change: a renewal, a refund, an approved Ask to Buy, a purchase on
    /// another device. Every caller gets its own stream.
    func statusUpdates() async -> AsyncStream<SubscriptionStatus>
    /// What to show on the paywall.
    func offer() async throws(SubscriptionProblem) -> SubscriptionOffer
    /// Buys the monthly subscription through Apple's sheet.
    func purchase() async -> PurchaseOutcome
    /// Restore purchases: asks the App Store to sync, then reads the status again. Apple may ask
    /// her to sign in. Only when she taps it.
    func restore() async throws(SubscriptionProblem) -> SubscriptionStatus
    /// 30b: after Apple's offer code sheet says a code was redeemed. Finishes what the redemption
    /// delivered, reads the status again and tells every listener.
    func redeemedOfferCode() async -> SubscriptionStatus
}

/// Keeps the last status between launches, so the app can show it before StoreKit answers.
/// `hasStylingAccess(at:)` keeps a cached status from granting past its own dates.
public protocol SubscriptionStatusCache: Sendable {
    func load() -> SubscriptionStatus?
    func save(_ status: SubscriptionStatus)
}

/// A cache that lasts as long as the process. For tests and previews.
public final class InMemorySubscriptionStatusCache: SubscriptionStatusCache {
    private let stored: Mutex<SubscriptionStatus?>

    public init(_ status: SubscriptionStatus? = nil) {
        stored = Mutex(status)
    }

    public func load() -> SubscriptionStatus? { stored.withLock { $0 } }
    public func save(_ status: SubscriptionStatus) { stored.withLock { $0 = status } }
}

/// No store in this build: never subscribed, and nothing to buy. The default until the app sets
/// the real one.
public struct UnavailableSubscriptionService: SubscriptionService {
    public init() {}
    public func subscriptionGroupID() async -> String? { nil }
    public func cachedStatus() async -> SubscriptionStatus { .none(at: Date()) }
    public func refresh() async -> SubscriptionStatus { .none(at: Date()) }
    public func statusUpdates() async -> AsyncStream<SubscriptionStatus> { AsyncStream { $0.finish() } }
    public func offer() async throws(SubscriptionProblem) -> SubscriptionOffer { throw .unavailable }
    public func purchase() async -> PurchaseOutcome { .failed(.unavailable) }
    public func restore() async throws(SubscriptionProblem) -> SubscriptionStatus { throw .unavailable }
    public func redeemedOfferCode() async -> SubscriptionStatus { .none(at: Date()) }
}

/// The try-on picture allowance (PRD 14.4) as the try-on sheet shows it.
public enum TryOnAllowance: Sendable, Equatable {
    /// Simulated pictures on the phone cost nothing (until the image service, Phase 33).
    case freeSimulated
    /// Pictures come with styling access: this many a month. The server counts them (24b).
    case included(perMonth: Int)
    /// 30b: the picture uses 1 of her purchased credits (the month's are used, or she has no
    /// styling access). This many are left.
    case credits(Int)
    /// 30b: styling access, but this month's pictures are used and she has no credits.
    case allowanceUsed
    /// Pictures need styling access, which she doesn't have now.
    case needsStylingAccess

    /// The allowance for a status at `now`, spending the month's pictures first, then credits
    /// (`TryOnFunding`). While pictures are simulated nothing is charged, so neither matters.
    /// - Parameter usage: what the server last said is left, with her credits. Nil when unknown.
    public static func current(
        status: SubscriptionStatus, picturesAreSimulated: Bool, at now: Date,
        allowances: StylingAllowances = .placeholder, usage: CloudUsage? = nil
    ) -> TryOnAllowance {
        if picturesAreSimulated { return .freeSimulated }
        let hasAccess = status.hasStylingAccess(at: now)
        let credits = usage?.credits
        switch TryOnFunding.next(
            hasAccess: hasAccess, allowanceLeft: usage?.allowance(.tryOn)?.remainingToday, credits: credits)
        {
        case .allowance: return .included(perMonth: allowances.tryOnPerMonth)
        case .credit: return .credits(credits ?? 0)
        case .nothing: return hasAccess ? .allowanceUsed : .needsStylingAccess
        }
    }

    /// Whether a picture can be made now.
    public var canMake: Bool {
        switch self {
        case .freeSimulated, .included, .credits: true
        case .allowanceUsed, .needsStylingAccess: false
        }
    }
}

/// What styling access includes, as the paywall and Help say it. PLACEHOLDERS: the numbers match
/// the backend's development allowances (24b, PRD 11.6) until Jose approves the production ones
/// (decision D12). The server enforces its own numbers either way.
public struct StylingAllowances: Sendable, Equatable {
    /// Style Me requests a day.
    public var styleMePerDay: Int
    /// Swaps and Ask stylist questions a day.
    public var swapsAndQuestionsPerDay: Int
    /// Try-on pictures a month.
    public var tryOnPerMonth: Int

    public init(styleMePerDay: Int, swapsAndQuestionsPerDay: Int, tryOnPerMonth: Int) {
        self.styleMePerDay = styleMePerDay
        self.swapsAndQuestionsPerDay = swapsAndQuestionsPerDay
        self.tryOnPerMonth = tryOnPerMonth
    }

    /// PLACEHOLDER values, to be replaced by Jose's decision.
    public static let placeholder = StylingAllowances(styleMePerDay: 10, swapsAndQuestionsPerDay: 40, tryOnPerMonth: 30)
}
