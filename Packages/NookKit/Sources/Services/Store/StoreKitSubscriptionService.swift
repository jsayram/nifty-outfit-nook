import Foundation
import Models
import StoreKit
import Synchronization
import UIKit

/// The styling subscription through StoreKit 2 (Phase 30a).
///
/// - Reads the status from `Product.SubscriptionInfo.status` (which tells a grace period and
///   billing retry apart), and falls back to the latest transaction when StoreKit has no status
///   yet. Only verified transactions count; an unverified one is finished and ignored.
/// - `start()` listens to `Transaction.updates` for the life of the app: renewals, refunds, an
///   approved Ask to Buy, a purchase on another device. Each update is finished, the status read
///   again, cached, and sent to every `statusUpdates()` stream.
/// - The cache only lets the app show a status before StoreKit answers. `hasStylingAccess(at:)`
///   never grants past the dates Apple gave, so a stale cache can't stretch access.
/// - Nothing here is proof for the server: paid requests carry the status as a hint, and the
///   server checks Apple's records itself (30c).
public final class StoreKitSubscriptionService: SubscriptionService {
    private let productID: String
    private let cache: any SubscriptionStatusCache
    private let now: @Sendable () -> Date
    /// How long after a purchase an empty answer from StoreKit is taken as StoreKit catching up
    /// rather than as "nothing bought". A just-bought status is kept that long, never past its
    /// own dates.
    private let catchUpWindow: TimeInterval
    /// Restore's sync with the App Store. `AppStore.sync()` in the app; it can ask her to sign in
    /// to her Apple Account, so tests (which must never sign in) pass their own.
    private let sync: @Sendable () async throws -> Void
    private let state = Mutex(State())

    private struct State {
        var product: Product?
        var listener: Task<Void, Never>?
        var streams: [UUID: AsyncStream<Models.SubscriptionStatus>.Continuation] = [:]
        /// When the last verified purchase in this process happened.
        var purchasedAt: Date?
    }

    /// - Parameters:
    ///   - sync: what Restore purchases asks the App Store to do. Tests pass their own.
    ///   - now: the clock. Tests pass their own.
    public init(
        productID: String = SubscriptionProducts.monthly, cache: any SubscriptionStatusCache,
        catchUpWindow: TimeInterval = 60,
        sync: @escaping @Sendable () async throws -> Void = { try await AppStore.sync() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.productID = productID
        self.cache = cache
        self.catchUpWindow = catchUpWindow
        self.sync = sync
        self.now = now
    }

    deinit {
        state.withLock { $0.listener?.cancel() }
    }

    /// Starts listening to `Transaction.updates`. Call once, at launch, before anything else
    /// reads the status, so no transaction that arrives at launch is missed. Calling again does
    /// nothing.
    public func start() {
        state.withLock { state in
            guard state.listener == nil else { return }
            state.listener = Task.detached(priority: .utility) { [weak self] in
                for await update in Transaction.updates {
                    await self?.handle(update)
                }
            }
        }
    }

    /// Stops listening and ends every status stream. For tests.
    public func stop() {
        let streams = state.withLock { state in
            state.listener?.cancel()
            state.listener = nil
            defer { state.streams = [:] }
            return Array(state.streams.values)
        }
        for stream in streams { stream.finish() }
    }

    // MARK: SubscriptionService

    public func subscriptionGroupID() async -> String? {
        try? await product().subscription?.subscriptionGroupID
    }

    public func cachedStatus() async -> Models.SubscriptionStatus {
        cache.load() ?? .none(at: now())
    }

    public func refresh() async -> Models.SubscriptionStatus {
        let read = await readStatus()
        let kept = keepJustBought(over: read)
        cache.save(kept)
        return kept
    }

    public func statusUpdates() async -> AsyncStream<Models.SubscriptionStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: Models.SubscriptionStatus.self)
        let id = UUID()
        state.withLock { $0.streams[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.streams.removeValue(forKey: id) }
        }
        return stream
    }

    public func offer() async throws(SubscriptionProblem) -> SubscriptionOffer {
        let product: Product
        do {
            product = try await self.product()
        } catch {
            throw Self.problem(for: error)
        }
        guard let subscription = product.subscription else { throw .unavailable }
        var trial: Models.SubscriptionPeriod?
        if let intro = subscription.introductoryOffer, intro.paymentMode == .freeTrial,
            await subscription.isEligibleForIntroOffer
        {
            trial = Self.period(intro.period)
        }
        return SubscriptionOffer(
            productID: product.id, displayName: product.displayName, displayPrice: product.displayPrice,
            period: Self.period(subscription.subscriptionPeriod), freeTrial: trial)
    }

    public func purchase() async -> PurchaseOutcome {
        let product: Product
        do {
            product = try await self.product()
        } catch {
            return .failed(Self.problem(for: error))
        }
        let result: Product.PurchaseResult
        do {
            result = try await Self.buy(product)
        } catch {
            return .failed(Self.problem(for: error))
        }
        switch result {
        case .success(.verified(let transaction)):
            // Read the status from the transaction itself: StoreKit's status can take a moment
            // to catch up after a purchase.
            let status = await statusAfterPurchase(transaction)
            await transaction.finish()
            state.withLock { $0.purchasedAt = now() }
            cache.save(status)
            broadcast(status)
            return .purchased(status)
        case .success(.unverified(let transaction, _)):
            // Never granted. Finished so it doesn't come back on every launch.
            await transaction.finish()
            return .failed(.unverified)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .failed(.failed)
        }
    }

    public func restore() async throws(SubscriptionProblem) -> Models.SubscriptionStatus {
        do {
            try await sync()
        } catch {
            throw Self.problem(for: error)
        }
        let status = await refresh()
        broadcast(status)
        return status
    }

    // MARK: Reading StoreKit

    private func product() async throws -> Product {
        if let product = state.withLock({ $0.product }) { return product }
        guard let product = try await Product.products(for: [productID]).first else {
            throw SubscriptionProblem.unavailable
        }
        state.withLock { $0.product = product }
        return product
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        switch update {
        case .verified(let transaction):
            await transaction.finish()
        case .unverified(let transaction, _):
            await transaction.finish()
        }
        let status = await refresh()
        broadcast(status)
    }

    /// The status StoreKit reports now, or the cached one (bounded by its own dates) when
    /// StoreKit can't be read at all.
    private func readStatus() async -> Models.SubscriptionStatus {
        let checked = now()
        if let product = try? await product(), let subscription = product.subscription,
            let statuses = try? await subscription.status
        {
            let mapped = await statuses.asyncCompactMap { await Self.status(from: $0, checkedAt: checked) }
            if let best = Self.best(mapped, at: checked) { return best }
        }
        // No status yet: the latest verified transaction, if any.
        if let latest = await Transaction.latest(for: productID) {
            guard case .verified(let transaction) = latest else { return .none(at: checked) }
            return Self.status(from: transaction, renewal: nil, checkedAt: checked)
        }
        return .none(at: checked)
    }

    /// Right after a purchase StoreKit can still say "nothing". The verified purchase stays for
    /// `catchUpWindow`, and never past its own dates.
    private func keepJustBought(over read: Models.SubscriptionStatus) -> Models.SubscriptionStatus {
        guard read.state == .none, let purchasedAt = state.withLock({ $0.purchasedAt }),
            now().timeIntervalSince(purchasedAt) < catchUpWindow,
            let cached = cache.load(), cached.hasStylingAccess(at: now())
        else { return read }
        return cached
    }

    private func statusAfterPurchase(_ transaction: Transaction) async -> Models.SubscriptionStatus {
        var status = Self.status(from: transaction, renewal: nil, checkedAt: now())
        status.willAutoRenew = transaction.revocationDate == nil
        return status
    }

    private func broadcast(_ status: Models.SubscriptionStatus) {
        let streams = state.withLock { Array($0.streams.values) }
        for stream in streams { stream.yield(status) }
    }

    // MARK: Mapping

    static func status(from status: Product.SubscriptionInfo.Status, checkedAt: Date) async -> Models
        .SubscriptionStatus?
    {
        guard case .verified(let transaction) = status.transaction else { return nil }
        let renewal: Product.SubscriptionInfo.RenewalInfo? =
            if case .verified(let info) = status.renewalInfo { info } else { nil }
        var mapped = Self.status(from: transaction, renewal: renewal, checkedAt: checkedAt)
        switch status.state {
        case .subscribed:
            if mapped.state == .expired || mapped.state == .none {
                mapped.state = Self.isTrial(transaction) ? .trial : .active
            }
        case .inGracePeriod:
            mapped.state = .gracePeriod
            mapped.gracePeriodEndsAt = renewal?.gracePeriodExpirationDate
        case .inBillingRetryPeriod:
            mapped.state = .billingRetry
        case .expired:
            mapped.state = .expired
        case .revoked:
            mapped.state = .revoked
        default:
            break
        }
        if transaction.revocationDate != nil { mapped.state = .revoked }
        return mapped
    }

    static func status(
        from transaction: Transaction, renewal: Product.SubscriptionInfo.RenewalInfo?, checkedAt: Date
    ) -> Models.SubscriptionStatus {
        let state: SubscriptionState
        if transaction.revocationDate != nil {
            state = .revoked
        } else if let expires = transaction.expirationDate, expires > checkedAt {
            state = isTrial(transaction) ? .trial : .active
        } else {
            state = .expired
        }
        return Models.SubscriptionStatus(
            state: state, productID: transaction.productID, expiresAt: transaction.expirationDate,
            willAutoRenew: renewal?.willAutoRenew ?? false, checkedAt: checkedAt)
    }

    static func isTrial(_ transaction: Transaction) -> Bool {
        transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial
    }

    /// The status that gives the most, when there's more than one (Family Sharing).
    static func best(_ statuses: [Models.SubscriptionStatus], at now: Date) -> Models.SubscriptionStatus? {
        func rank(_ status: Models.SubscriptionStatus) -> Int {
            if status.hasStylingAccess(at: now) { return 3 }
            switch status.state {
            case .billingRetry: return 2
            case .expired, .revoked: return 1
            default: return 0
            }
        }
        return statuses.max { rank($0) < rank($1) }
    }

    static func period(_ period: Product.SubscriptionPeriod) -> Models.SubscriptionPeriod {
        let unit: Models.SubscriptionPeriod.Unit =
            switch period.unit {
            case .day: .day
            case .week: .week
            case .month: .month
            case .year: .year
            @unknown default: .month
            }
        return Models.SubscriptionPeriod(period.value, unit)
    }

    static func problem(for error: any Error) -> SubscriptionProblem {
        if let problem = error as? SubscriptionProblem { return problem }
        if let error = error as? StoreKitError {
            switch error {
            case .networkError: return .offline
            case .notAvailableInStorefront, .notEntitled: return .unavailable
            case .userCancelled: return .failed
            default: return .failed
            }
        }
        if let error = error as? Product.PurchaseError {
            switch error {
            case .purchaseNotAllowed: return .notAllowed
            case .productUnavailable: return .unavailable
            default: return .failed
            }
        }
        if (error as NSError).domain == NSURLErrorDomain { return .offline }
        return .failed
    }

    /// Apple's sheet, shown over the active window when there is one.
    @MainActor private static func buy(_ product: Product) async throws -> Product.PurchaseResult {
        let scene =
            UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        if let scene {
            return try await product.purchase(confirmIn: scene)
        }
        return try await product.purchase()
    }
}

extension Sequence where Element: Sendable {
    fileprivate func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var results: [T] = []
        for element in self {
            if let value = await transform(element) { results.append(value) }
        }
        return results
    }
}
