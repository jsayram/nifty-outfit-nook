import Foundation
import Models
import Synchronization

/// A subscription that follows a script, for snapshot and model tests and for debug launches
/// (`-subscription <state>`). Nothing is bought: a purchase moves to the scripted outcome.
public final class ScriptedSubscriptionService: SubscriptionService {
    private struct State {
        var status: SubscriptionStatus
        var offer: SubscriptionOffer?
        var purchase: PurchaseOutcome
        var restore: Result<SubscriptionStatus, SubscriptionProblem>?
        var streams: [UUID: AsyncStream<SubscriptionStatus>.Continuation] = [:]
        var purchases = 0
        var restores = 0
        /// 30b: what redeeming an offer code gives. Nil changes nothing.
        var redemption: SubscriptionStatus?
        var redemptions = 0
    }

    private let state: Mutex<State>
    private let groupID: String?

    /// - Parameters:
    ///   - purchase: what a purchase does. `nil` starts the free month (or a paid month when the
    ///     offer has no trial) from the offer, at the status's `checkedAt`.
    public init(
        status: SubscriptionStatus, offer: SubscriptionOffer? = .sample, purchase: PurchaseOutcome? = nil,
        restore: Result<SubscriptionStatus, SubscriptionProblem>? = nil, groupID: String? = "21000001"
    ) {
        let bought = purchase ?? Self.bought(offer: offer, at: status.checkedAt)
        state = Mutex(State(status: status, offer: offer, purchase: bought, restore: restore))
        self.groupID = groupID
    }

    /// How many purchases and restores were asked for.
    public var purchaseCount: Int { state.withLock { $0.purchases } }
    public var restoreCount: Int { state.withLock { $0.restores } }
    public var redemptionCount: Int { state.withLock { $0.redemptions } }

    /// 30b: what the next offer code redemption gives, as Apple's sheet would.
    public func scriptRedemption(_ status: SubscriptionStatus?) {
        state.withLock { $0.redemption = status }
    }

    /// Changes the status, as a renewal, a refund or another device would, and tells every stream.
    public func update(_ status: SubscriptionStatus) {
        let streams = state.withLock { state in
            state.status = status
            return Array(state.streams.values)
        }
        for stream in streams { stream.yield(status) }
    }

    public func subscriptionGroupID() async -> String? { groupID }
    public func cachedStatus() async -> SubscriptionStatus { state.withLock { $0.status } }
    public func refresh() async -> SubscriptionStatus { state.withLock { $0.status } }

    public func statusUpdates() async -> AsyncStream<SubscriptionStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: SubscriptionStatus.self)
        let id = UUID()
        state.withLock { $0.streams[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.streams.removeValue(forKey: id) }
        }
        return stream
    }

    public func offer() async throws(SubscriptionProblem) -> SubscriptionOffer {
        guard let offer = state.withLock({ $0.offer }) else { throw .unavailable }
        return offer
    }

    public func purchase() async -> PurchaseOutcome {
        let outcome = state.withLock { state in
            state.purchases += 1
            if case .purchased(let status) = state.purchase { state.status = status }
            return state.purchase
        }
        if case .purchased(let status) = outcome { update(status) }
        return outcome
    }

    public func restore() async throws(SubscriptionProblem) -> SubscriptionStatus {
        let result = state.withLock { state in
            state.restores += 1
            return state.restore ?? .success(state.status)
        }
        switch result {
        case .success(let status):
            update(status)
            return status
        case .failure(let problem):
            throw problem
        }
    }

    public func redeemedOfferCode() async -> SubscriptionStatus {
        let status = state.withLock { state in
            state.redemptions += 1
            if let redeemed = state.redemption { state.status = redeemed }
            return state.status
        }
        update(status)
        return status
    }

    private static func bought(offer: SubscriptionOffer?, at date: Date) -> PurchaseOutcome {
        guard let offer else { return .failed(.unavailable) }
        let calendar = Calendar(identifier: .gregorian)
        let trial = offer.freeTrial != nil
        return .purchased(
            SubscriptionStatus(
                state: trial ? .trial : .active, productID: offer.productID,
                expiresAt: (offer.freeTrial ?? offer.period).end(from: date, calendar: calendar),
                willAutoRenew: true, checkedAt: date))
    }
}

extension SubscriptionOffer {
    /// The sample offer: the local StoreKit configuration's PLACEHOLDER price and the PRD's free
    /// month.
    public static let sample = SubscriptionOffer(
        productID: SubscriptionProducts.monthly, displayName: "Styling, monthly", displayPrice: "$9.99",
        period: SubscriptionPeriod(1, .month), freeTrial: SubscriptionPeriod(1, .month))
}

extension ScriptedSubscriptionService {
    /// A scripted subscription for a debug launch: `-subscription none|trial|active|grace|retry|
    /// expired|revoked|used-trial|complimentary`, dated from `now`. Redeeming a code (30b) always
    /// gives the complimentary unlock.
    public static func debug(_ name: String, now: Date) -> ScriptedSubscriptionService {
        let calendar = Calendar(identifier: .gregorian)
        let monthLater = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        let daysLater = calendar.date(byAdding: .day, value: 12, to: now) ?? now
        let monthBefore = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let id = SubscriptionProducts.monthly
        let status: SubscriptionStatus =
            switch name {
            case "trial":
                SubscriptionStatus(
                    state: .trial, productID: id, expiresAt: daysLater, willAutoRenew: true, checkedAt: now)
            case "active":
                SubscriptionStatus(
                    state: .active, productID: id, expiresAt: monthLater, willAutoRenew: true, checkedAt: now)
            case "grace":
                SubscriptionStatus(
                    state: .gracePeriod, productID: id, expiresAt: now,
                    gracePeriodEndsAt: calendar.date(byAdding: .day, value: 6, to: now), willAutoRenew: true,
                    checkedAt: now)
            case "retry":
                SubscriptionStatus(
                    state: .billingRetry, productID: id, expiresAt: now, willAutoRenew: true, checkedAt: now)
            case "expired":
                SubscriptionStatus(state: .expired, productID: id, expiresAt: monthBefore, checkedAt: now)
            case "revoked":
                SubscriptionStatus(state: .revoked, productID: id, expiresAt: monthLater, checkedAt: now)
            case "complimentary":
                SubscriptionStatus(state: .none, checkedAt: now, complimentarySince: now)
            default:
                .none(at: now)
            }
        var offer = SubscriptionOffer.sample
        if name != "none" && name != "complimentary" { offer.freeTrial = nil }
        let service = ScriptedSubscriptionService(status: status, offer: offer)
        var redeemed = status
        redeemed.complimentarySince = status.complimentarySince ?? now
        service.scriptRedemption(redeemed)
        return service
    }
}
