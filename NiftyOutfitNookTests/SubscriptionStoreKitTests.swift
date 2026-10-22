import Foundation
import Models
import Services
import StoreKit
import StoreKitTest
import Synchronization
import Testing

/// Phase 30a: the styling subscription against StoreKit's local test environment
/// (`NiftyOutfitNook.storekit`, `SKTestSession`), with no dialogs and accelerated time where a
/// renewal has to happen. This is the plan's checkpoint, "sandbox purchase, restore, renewal and
/// expiry", in Xcode's StoreKit testing instead of Apple's sandbox, which needs App Store Connect.
///
/// The tests share one test environment (SKTestSession is a single instance), so they run one at a
/// time. StoreKit takes a moment to report a change after it happens, so checks of what StoreKit
/// says wait for it, up to a limit; checks of the app's own rules use an injected clock.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct SubscriptionStoreKitTests {
    static let product = SubscriptionProducts.monthly

    // MARK: The offer

    @Test func offerComesFromTheStoreWithTheFreeMonth() async throws {
        let (_, service, _) = try setUp()
        let offer = try await service.offer()
        #expect(offer.productID == Self.product)
        #expect(offer.displayPrice == "$9.99")
        #expect(offer.period == Models.SubscriptionPeriod(1, .month))
        #expect(offer.freeTrial == Models.SubscriptionPeriod(1, .month))
        #expect(await service.subscriptionGroupID() != nil)
        #expect(await service.refresh().state == .none)
    }

    // MARK: Purchase and the free month

    @Test func purchaseStartsTheFreeMonth() async throws {
        let (_, service, cache) = try setUp()
        let outcome = await service.purchase()
        guard case .purchased(let status) = outcome else {
            Issue.record("Expected a purchase, got \(outcome)")
            return
        }
        #expect(status.state == .trial)
        #expect(status.productID == Self.product)
        #expect(status.willAutoRenew)
        #expect(status.hasStylingAccess(at: Date()))
        #expect(cache.load() == status)
        // StoreKit catches up and says the same.
        #expect(await eventually { await service.refresh().state == .trial })
        // The free month is used: the offer now says the price only.
        #expect(await eventually { (try? await service.offer())?.freeTrial == nil })
    }

    @Test func accessEndsAtTheDateAppleGaveEvenWithoutAnUpdate() async throws {
        let clock = TestClock()
        let (_, service, _) = try setUp(clock: clock)
        guard case .purchased(let status) = await service.purchase(), let end = status.expiresAt else {
            Issue.record("Expected a purchase with an end date")
            return
        }
        #expect(await service.cachedStatus().hasStylingAccess(at: clock.now()))
        // Past the end, with nothing new from StoreKit: the cached status grants nothing.
        clock.set(end.addingTimeInterval(1))
        let cached = await service.cachedStatus()
        #expect(!cached.hasStylingAccess(at: clock.now()))
        #expect(cached.effectiveState(at: clock.now()) == .expired)
        #expect(cached.hint(at: clock.now()) == .expired)
    }

    // MARK: Renewal, expiry, refund

    @Test func renewalMovesToAPaidMonth() async throws {
        let (session, service, _) = try setUp()
        guard case .purchased(let first) = await service.purchase(), let firstEnd = first.expiresAt else {
            Issue.record("Expected a purchase")
            return
        }
        try session.forceRenewalOfSubscription(productIdentifier: Self.product)
        #expect(
            await eventually {
                let status = await service.refresh()
                return status.state == .active && (status.expiresAt ?? .distantPast) > firstEnd
            })
        #expect(await service.refresh().hasStylingAccess(at: Date()))
    }

    @Test func expiryTurnsAccessOff() async throws {
        let (session, service, _) = try setUp()
        _ = await service.purchase()
        try session.expireSubscription(productIdentifier: Self.product)
        #expect(await eventually { await service.refresh().state == .expired })
        #expect(!(await service.refresh().hasStylingAccess(at: Date())))
    }

    @Test func refundRevokesAccessThroughTheUpdatesListener() async throws {
        let (session, service, _) = try setUp()
        service.start()
        defer { service.stop() }
        let updates = await service.statusUpdates()
        _ = await service.purchase()
        let bought = try #require(session.allTransactions().last)
        try session.refundTransaction(identifier: bought.identifier)
        #expect(await eventually { await service.refresh().state == .revoked })
        #expect(!(await service.refresh().hasStylingAccess(at: Date())))
        // The listener heard it and told the app.
        let heard = await first(of: updates) { $0.state == .revoked }
        #expect(heard?.state == .revoked)
    }

    // MARK: Billing problems

    @Test func gracePeriodKeepsAccessUntilItEnds() async throws {
        let (session, service, _) = try setUp()
        session.billingGracePeriodIsEnabled = true
        session.shouldEnterBillingRetryOnRenewal = true
        _ = await service.purchase()
        try session.forceRenewalOfSubscription(productIdentifier: Self.product)
        #expect(await eventually { await service.refresh().state == .gracePeriod })
        let status = await service.refresh()
        #expect(status.hasStylingAccess(at: Date()))
        #expect(status.hint(at: Date()) == .grace)
        #expect(status.mayRenew)
    }

    @Test func billingRetryWithoutGraceTurnsAccessOff() async throws {
        let (session, service, _) = try setUp()
        session.shouldEnterBillingRetryOnRenewal = true
        _ = await service.purchase()
        try session.forceRenewalOfSubscription(productIdentifier: Self.product)
        #expect(await eventually { await service.refresh().state == .billingRetry })
        let status = await service.refresh()
        #expect(!status.hasStylingAccess(at: Date()))
        // Apple is still trying to charge, so Delete my account still warns.
        #expect(status.mayRenew)
    }

    // MARK: Restore and Ask to Buy

    @Test func restoreFindsTheSubscriptionOnAFreshInstall() async throws {
        let (_, service, _) = try setUp()
        _ = await service.purchase()
        // A fresh install: nothing cached, a new service.
        let reinstalled = Self.reinstalled()
        #expect(await reinstalled.cachedStatus().state == .none)
        #expect(
            await eventually {
                (try? await reinstalled.restore())?.state == .trial
            })
    }

    @Test func askToBuyWaitsThenStartsWhenApproved() async throws {
        let (session, service, _) = try setUp()
        session.askToBuyEnabled = true
        service.start()
        defer { service.stop() }
        let updates = await service.statusUpdates()
        #expect(await service.purchase() == .pending)
        #expect(!(await service.refresh().hasStylingAccess(at: Date())))
        let asked = try #require(session.allTransactions().last)
        try session.approveAskToBuyTransaction(identifier: asked.identifier)
        let started = await first(of: updates) { $0.hasStylingAccess(at: Date()) }
        #expect(started?.state == .trial)
    }

    // MARK: The checkpoint

    /// Purchase, a renewal that StoreKit makes on its own with accelerated time, restore on a
    /// fresh install, and expiry, one after the other.
    @Test(.timeLimit(.minutes(2)))
    func checkpointPurchaseRenewRestoreExpire() async throws {
        let (session, service, _) = try setUp()
        session.timeRate = .monthlyRenewalEveryThirtySeconds
        guard case .purchased(let trial) = await service.purchase(), let trialEnd = trial.expiresAt else {
            Issue.record("Expected a purchase")
            return
        }
        #expect(trial.state == .trial)
        // A month is 30 seconds now; StoreKit renews by itself.
        #expect(trialEnd.timeIntervalSince(Date()) < 60)
        #expect(
            await eventually(.seconds(75)) {
                let status = await service.refresh()
                return status.state == .active && (status.expiresAt ?? .distantPast) > trialEnd
            })
        let reinstalled = Self.reinstalled()
        #expect(await eventually { (try? await reinstalled.restore())?.state == .active })
        try session.expireSubscription(productIdentifier: Self.product)
        #expect(await eventually { await reinstalled.refresh().state == .expired })
        #expect(!(await reinstalled.refresh().hasStylingAccess(at: Date())))
    }

    // MARK: Helpers

    /// A fresh install: nothing cached, a new service. Its Restore skips `AppStore.sync()`, which
    /// asks for an Apple Account sign-in that a test must never answer; StoreKit's test
    /// environment already holds the transactions, so the restore reads them as the app would
    /// after a real sync.
    static func reinstalled() -> StoreKitSubscriptionService {
        StoreKitSubscriptionService(cache: InMemorySubscriptionStatusCache(), sync: {})
    }

    private func setUp(clock: TestClock = TestClock()) throws -> (
        SKTestSession, StoreKitSubscriptionService, InMemorySubscriptionStatusCache
    ) {
        let url = try #require(
            Bundle(for: BundleMarker.self).url(forResource: "NiftyOutfitNook", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let cache = InMemorySubscriptionStatusCache()
        let service = StoreKitSubscriptionService(cache: cache, sync: {}, now: { clock.now() })
        return (session, service, cache)
    }

    /// Asks again until `check` is true or `limit` passes. StoreKit reports a change a moment
    /// after it happens.
    private func eventually(_ limit: Duration = .seconds(20), _ check: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if await check() { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return await check()
    }

    /// The first status from `stream` that matches, or nil after `limit`.
    private func first(
        of stream: AsyncStream<Models.SubscriptionStatus>, limit: Duration = .seconds(20),
        where match: @escaping @Sendable (Models.SubscriptionStatus) -> Bool
    ) async -> Models.SubscriptionStatus? {
        await withTaskGroup(of: Models.SubscriptionStatus?.self) { group in
            group.addTask {
                for await status in stream where match(status) { return status }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let found = await group.next() ?? nil
            group.cancelAll()
            return found
        }
    }
}

/// Finds this test bundle, which holds the StoreKit configuration file.
private final class BundleMarker {}

/// A clock a test can move forward: the real time plus an offset.
final class TestClock: Sendable {
    private let fixed = Mutex<Date?>(nil)

    func now() -> Date { fixed.withLock { $0 } ?? Date() }
    func set(_ date: Date) { fixed.withLock { $0 = date } }
}
