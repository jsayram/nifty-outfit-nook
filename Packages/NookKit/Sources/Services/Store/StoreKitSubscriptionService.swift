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
///   approved Ask to Buy, a purchase on another device, a redeemed offer code. Each update is
///   finished, the status read again, cached, and sent to every `statusUpdates()` stream. Picture
///   packs (consumables) are left alone: `StoreKitCreditsService` finishes them only once the
///   server has credited them (30b).
/// - 30b: the complimentary unlock (a non-consumable from an offer code) is read from
///   `Transaction.currentEntitlements`, which leaves out anything Apple refunded or revoked.
/// - The cache only lets the app show a status before StoreKit answers. `hasStylingAccess(at:)`
///   never grants past the dates Apple gave, so a stale cache can't stretch access.
/// - Nothing here is proof for the server: paid requests carry the status as a hint, and the
///   server checks Apple's records itself (30c).
/// - 30c: purchases carry the account's `appAccountToken` (from the server), so Apple's server
///   notifications name the account; and every read of the status sends the subscription's and
///   the unlock's signed transactions to the server once per launch (`StylingAccessClaiming`),
///   which is how an offer-code unlock, or a purchase made signed out, reaches the account.
public final class StoreKitSubscriptionService: SubscriptionService {
    private let productID: String
    private let complimentaryID: String
    private let cache: any SubscriptionStatusCache
    private let now: @Sendable () -> Date
    /// How long after a purchase an empty answer from StoreKit is taken as StoreKit catching up
    /// rather than as "nothing bought". A just-bought status is kept that long, never past its
    /// own dates.
    private let catchUpWindow: TimeInterval
    /// Restore's sync with the App Store. `AppStore.sync()` in the app; it can ask her to sign in
    /// to her Apple Account, so tests (which must never sign in) pass their own.
    private let sync: @Sendable () async throws -> Void
    /// 30c: the server's claim endpoint, and the token purchases carry. No claimer: nothing is sent.
    private let claimer: (any StylingAccessClaiming)?
    private let purchaseToken: PurchaseAccountToken
    private let state = Mutex(State())

    private struct State {
        var product: Product?
        var listener: Task<Void, Never>?
        var streams: [UUID: AsyncStream<Models.SubscriptionStatus>.Continuation] = [:]
        /// When the last verified purchase in this process happened.
        var purchasedAt: Date?
        /// 30c: transactions the server has taken in this process, so each is sent once.
        var claimed: Set<UInt64> = []
        var claiming = false
    }

    /// - Parameters:
    ///   - sync: what Restore purchases asks the App Store to do. Tests pass their own.
    ///   - now: the clock. Tests pass their own.
    public init(
        productID: String = SubscriptionProducts.monthly,
        complimentaryID: String = SubscriptionProducts.complimentary, cache: any SubscriptionStatusCache,
        catchUpWindow: TimeInterval = 60,
        sync: @escaping @Sendable () async throws -> Void = { try await AppStore.sync() },
        claimer: (any StylingAccessClaiming)? = nil, purchaseToken: PurchaseAccountToken = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.productID = productID
        self.complimentaryID = complimentaryID
        self.cache = cache
        self.catchUpWindow = catchUpWindow
        self.sync = sync
        self.claimer = claimer
        self.purchaseToken = purchaseToken
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
            // The iterator is made here, not inside the task: a task at utility priority can
            // start late on a busy machine, and an update that arrived before it began to iterate
            // was never delivered (measured on the iOS 26.5 simulator, 22 October 2026).
            nonisolated(unsafe) var updates = Transaction.updates.makeAsyncIterator()
            state.listener = Task.detached(priority: .utility) { [weak self] in
                while let update = await updates.next() {
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
        claimWithServer()
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
            result = try await Self.buy(product, options: Self.purchaseOptions(token: purchaseToken.current))
        } catch {
            return .failed(Self.problem(for: error))
        }
        switch result {
        case .success(.verified(let transaction)):
            defer { claimWithServer() }
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

    public func redeemedOfferCode() async -> Models.SubscriptionStatus {
        // The redemption's transaction may be here already, or still on its way through
        // `Transaction.updates` (before iOS 27 the sheet doesn't return it). Finish what's here;
        // the listener finishes the rest and tells every screen.
        for await result in Transaction.unfinished {
            let transaction = result.unsafePayloadValue
            guard transaction.productType != .consumable else { continue }
            await transaction.finish()
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
        // 30b: a picture pack is finished only after the server credits it (StoreKitCreditsService).
        if update.unsafePayloadValue.productType == .consumable { return }
        switch update {
        case .verified(let transaction):
            await transaction.finish()
        case .unverified(let transaction, _):
            await transaction.finish()
        }
        let status = await refresh()
        broadcast(status)
    }

    /// The subscription's status and the complimentary unlock, as StoreKit reports them now.
    private func readStatus() async -> Models.SubscriptionStatus {
        var status = await readSubscription()
        status.complimentarySince = await complimentarySince()
        return status
    }

    /// 30b: when the complimentary unlock was redeemed, if she has it. Only a verified, unrevoked
    /// entitlement counts.
    private func complimentarySince() async -> Date? {
        for await result in Transaction.currentEntitlements(for: complimentaryID) {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                return transaction.purchaseDate
            }
        }
        return nil
    }

    /// The subscription's status from StoreKit.
    private func readSubscription() async -> Models.SubscriptionStatus {
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
            var cached = cache.load(), cached.hasStylingAccess(at: now())
        else { return read }
        cached.complimentarySince = read.complimentarySince
        return cached
    }

    private func statusAfterPurchase(_ transaction: Transaction) async -> Models.SubscriptionStatus {
        var status = Self.status(from: transaction, renewal: nil, checkedAt: now())
        status.willAutoRenew = transaction.revocationDate == nil
        status.complimentarySince = await complimentarySince()
        return status
    }

    /// 30c: sends the subscription's and the unlock's current signed transactions to the server,
    /// each once per launch, in the background. A failure (signed out, offline) is tried again at
    /// the next status read; the server takes a repeat as the same claim.
    private func claimWithServer() {
        guard let claimer else { return }
        let start = state.withLock { state -> Bool in
            guard !state.claiming else { return false }
            state.claiming = true
            return true
        }
        guard start else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.state.withLock { $0.claiming = false } }
            for id in [self.productID, self.complimentaryID] {
                for await result in Transaction.currentEntitlements(for: id) {
                    guard case .verified(let transaction) = result,
                        !self.state.withLock({ $0.claimed.contains(transaction.id) })
                    else { continue }
                    if (try? await claimer.claimStylingAccess(signedTransaction: result.jwsRepresentation)) != nil {
                        self.state.withLock { _ = $0.claimed.insert(transaction.id) }
                    }
                }
            }
        }
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

    /// 30c: what every purchase carries: the account's token when signed in, so Apple's server
    /// notifications can be matched to the account. Nothing else.
    public static func purchaseOptions(token: UUID?) -> Set<Product.PurchaseOption> {
        guard let token else { return [] }
        return [.appAccountToken(token)]
    }

    /// Apple's sheet, shown over the active window when there is one.
    @MainActor static func buy(_ product: Product, options: Set<Product.PurchaseOption>) async throws
        -> Product.PurchaseResult
    {
        let scene =
            UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        if let scene {
            return try await product.purchase(confirmIn: scene, options: options)
        }
        return try await product.purchase(options: options)
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
