import Foundation
import Models
import Services
import StoreKit
import StoreKitTest
import Synchronization
import Testing

/// Phase 30b: the complimentary unlock and picture packs against StoreKit's local test
/// environment (`NiftyOutfitNook.storekit`, `SKTestSession`), the plan's checkpoint "each purchase
/// type in sandbox" in Xcode's StoreKit testing instead of Apple's sandbox, which needs App Store
/// Connect.
///
/// The server's side is a small ledger here (`TestLedger`) that does what the backend's mocked
/// claim does (convex/credits.ts): it reads the transaction and product from the real StoreKit
/// JWS, checks it's a pack for this app, and credits each transaction ID once. The backend's own
/// tests check the endpoint itself.
///
/// Not on CI, like `SubscriptionStoreKitTests`: CI's iOS 27.0 simulator gets no products from
/// StoreKit's test environment. Run with `scripts/test.sh -only-testing:NiftyOutfitNookTests`.
///
/// Nested in `SubscriptionStoreKitTests` so its `.serialized` and CI traits cover these too: there
/// is one StoreKit test environment, so no two of these tests may run at once.
extension SubscriptionStoreKitTests {
@Suite struct CreditsStoreKitTests {
    // MARK: The complimentary unlock (an offer code)

    @Test func anOfferCodeRedemptionTurnsOnComplimentaryAccess() async throws {
        let session = try Self.session()
        let service = StoreKitSubscriptionService(cache: InMemorySubscriptionStatusCache(), sync: {})
        #expect(await service.refresh().hasStylingAccess(at: Date()) == false)
        // What Apple's offer code sheet does when she redeems a code for the unlock.
        let redeemed = try await session.buyProduct(
            identifier: SubscriptionProducts.complimentary, options: [.codeOffer(referenceName: "Family unlock")])
        #expect(redeemed.productType == .nonConsumable)
        // StoreKit lists the new entitlement a moment later; until then the listener would say.
        var status = await service.redeemedOfferCode()
        #expect(await eventually { status = await service.refresh(); return status.isComplimentary })
        #expect(status.hasStylingAccess(at: Date()))
        // No subscription: nothing renews or bills, and the hint says what it is.
        #expect(status.state == .none)
        #expect(!status.mayRenew)
        #expect(status.hint(at: Date()) == .complimentary)
        // A fresh install restores it from StoreKit's entitlements, with nothing cached.
        let reinstalled = StoreKitSubscriptionService(cache: InMemorySubscriptionStatusCache(), sync: {})
        #expect(await eventually { (try? await reinstalled.restore())?.isComplimentary == true })
    }

    @Test func aRefundedUnlockGivesNothing() async throws {
        let session = try Self.session()
        let service = StoreKitSubscriptionService(cache: InMemorySubscriptionStatusCache(), sync: {})
        try await session.buyProduct(
            identifier: SubscriptionProducts.complimentary, options: [.codeOffer(referenceName: "Family unlock")])
        _ = await service.redeemedOfferCode()
        #expect(await eventually { await service.refresh().isComplimentary })
        let unlock = try #require(session.allTransactions().last)
        try session.refundTransaction(identifier: unlock.identifier)
        #expect(await eventually { await service.refresh().isComplimentary == false })
        #expect(!(await service.refresh().hasStylingAccess(at: Date())))
    }

    @Test func theUnlockSitsAlongsideARenewingSubscription() async throws {
        let session = try Self.session()
        let service = StoreKitSubscriptionService(cache: InMemorySubscriptionStatusCache(), sync: {})
        guard case .purchased = await service.purchase() else {
            Issue.record("Expected the subscription to start")
            return
        }
        try await session.buyProduct(
            identifier: SubscriptionProducts.complimentary, options: [.codeOffer(referenceName: "Family unlock")])
        _ = await service.redeemedOfferCode()
        var status = await service.refresh()
        #expect(await eventually { status = await service.refresh(); return status.isComplimentary })
        // Both: the unlock doesn't cancel the subscription (the screen says so, PRD 14.2).
        #expect(status.state == .trial)
        #expect(status.mayRenew)
    }

    // MARK: Picture packs (consumables)

    @Test func packsComeFromTheStoreSmallestFirst() async throws {
        _ = try Self.session()
        let packs = try await StoreKitCreditsService(claimer: TestLedger()).packs()
        #expect(packs.map(\.productID) == [CreditPacks.small, CreditPacks.large])
        #expect(packs.map(\.displayPrice) == ["$2.99", "$6.99"])
        #expect(packs.map(\.pictures) == [10, 30])
    }

    @Test func aPackIsCreditedThenFinished() async throws {
        _ = try Self.session()
        let ledger = TestLedger()
        let credits = StoreKitCreditsService(claimer: ledger)
        let balances = await credits.balanceUpdates()
        #expect(await credits.purchase(CreditPacks.small) == .credited(pictures: 10, balance: 10))
        // A consumable can be bought again.
        #expect(await credits.purchase(CreditPacks.large) == .credited(pictures: 30, balance: 40))
        #expect(ledger.balance == 40)
        #expect(ledger.grants == 2)
        // Screens that listen hear the new balance.
        var heard: [Int] = []
        for await balance in balances {
            heard.append(balance)
            if heard.count == 2 { break }
        }
        #expect(heard == [10, 40])
    }

    @Test func aPackTheServerCouldNotCreditIsRecoveredAtTheNextLaunch() async throws {
        _ = try Self.session()
        let ledger = TestLedger()
        ledger.set(offline: true)
        let credits = StoreKitCreditsService(claimer: ledger)
        // Paid, but the server can't be reached: kept open, nothing credited.
        #expect(await credits.purchase(CreditPacks.small) == .awaitingCredit)
        #expect(ledger.balance == 0)
        // The next launch, with the server back. Recovery gets StoreKit's own signed transaction
        // (see `StoreKitCreditsService.unfinished` for why not from Transaction.unfinished here).
        ledger.set(offline: false)
        let open = try await Self.signed(CreditPacks.small)
        let relaunched = StoreKitCreditsService(claimer: TestLedger.sharing(ledger), unfinished: { [open] })
        #expect(await relaunched.recoverUnfinished() == 1)
        #expect(ledger.balance == 10)
    }

    @Test func aPackClaimedTwiceIsCreditedOnce() async throws {
        _ = try Self.session()
        let ledger = TestLedger()
        // The server credits it, but its answer never arrives (the app closed, the connection
        // dropped), so the transaction stays open and is claimed again at the next launch.
        ledger.loseNextAnswer()
        let credits = StoreKitCreditsService(claimer: ledger)
        #expect(await credits.purchase(CreditPacks.small) == .awaitingCredit)
        #expect(ledger.balance == 10)
        let open = try await Self.signed(CreditPacks.small)
        let relaunched = StoreKitCreditsService(claimer: ledger, unfinished: { [open] })
        // Credited before, so nothing new: the same grant comes back and the transaction finishes.
        #expect(await relaunched.recoverUnfinished() == 0)
        #expect(ledger.claims == 2)
        #expect(ledger.grants == 1)
        #expect(ledger.balance == 10)
    }

    @Test func theSubscriptionListenerLeavesPacksForTheCreditsService() async throws {
        let session = try Self.session()
        let subscriptions = StoreKitSubscriptionService(cache: InMemorySubscriptionStatusCache(), sync: {})
        subscriptions.start()
        defer { subscriptions.stop() }
        let updates = await subscriptions.statusUpdates()
        // Bought outside the app's own purchase call (as on another device, or an approved Ask to
        // Buy): it arrives through Transaction.updates. The unlock is bought too, so the
        // subscription listener has something to finish and report.
        try await session.buyProduct(identifier: CreditPacks.small)
        try await session.buyProduct(
            identifier: SubscriptionProducts.complimentary, options: [.codeOffer(referenceName: "Family unlock")])
        for await status in updates where status.isComplimentary { break }
        // The pack is still open for the credits service, which credits it from
        // Transaction.unfinished.
        let ledger = TestLedger()
        #expect(await StoreKitCreditsService(claimer: ledger).recoverUnfinished() == 1)
        #expect(ledger.balance == 10)
    }

    @Test func thePacksListenerCreditsAPackBoughtElsewhere() async throws {
        let session = try Self.session()
        let ledger = TestLedger()
        let credits = StoreKitCreditsService(claimer: ledger)
        credits.start()
        defer { credits.stop() }
        let balances = await credits.balanceUpdates()
        try await session.buyProduct(identifier: CreditPacks.large)
        for await balance in balances where balance == 30 { break }
        #expect(ledger.balance == 30)
        #expect(ledger.grants == 1)
    }

    // MARK: Helpers

    static func session() throws -> SKTestSession {
        let url = try #require(
            Bundle(for: CreditsBundleMarker.self).url(forResource: "NiftyOutfitNook", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    /// StoreKit's signed record of the latest purchase of a product. Consumables are in the
    /// history because the app sets `SKIncludeConsumableInAppPurchaseHistory`.
    static func signed(_ productID: String) async throws -> VerificationResult<Transaction> {
        // StoreKit lists a purchase in its history a moment after it returns it.
        for _ in 0..<40 {
            if let latest = await Transaction.latest(for: productID) { return latest }
            try await Task.sleep(for: .milliseconds(250))
        }
        return try #require(await Transaction.latest(for: productID))
    }

    private func eventually(_ limit: Duration = .seconds(20), _ check: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if await check() { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return await check()
    }
}
}

/// What the backend's mocked claim does (convex/credits.ts): the transaction and product come from
/// the JWS payload, only this app's consumable packs count, and each transaction ID is credited
/// once. It also checks StoreKit's JWS carries the fields the backend reads.
final class TestLedger: CreditClaiming {
    private struct State {
        var grants: [String: Int] = [:]
        var claims = 0
        var offline = false
        var loseNextAnswer = false
    }

    private let state: Mutex<State>
    private let shared: TestLedger?

    init() {
        state = Mutex(State())
        shared = nil
    }

    private init(sharing other: TestLedger) {
        state = Mutex(State())
        shared = other
    }

    /// Another claimer over the same ledger, as a relaunched app reaches the same server.
    static func sharing(_ other: TestLedger) -> TestLedger { TestLedger(sharing: other) }

    var balance: Int { (shared ?? self).state.withLock { $0.grants.values.reduce(0, +) } }
    var grants: Int { (shared ?? self).state.withLock { $0.grants.count } }
    var claims: Int { (shared ?? self).state.withLock { $0.claims } }
    func set(offline: Bool) { (shared ?? self).state.withLock { $0.offline = offline } }
    func loseNextAnswer() { (shared ?? self).state.withLock { $0.loseNextAnswer = true } }

    func claim(signedTransaction: String) async throws(CreditClaimProblem) -> CreditClaim {
        if let shared { return try await shared.claim(signedTransaction: signedTransaction) }
        guard let payload = Self.payload(signedTransaction), let id = payload["transactionId"] as? String,
            let product = payload["productId"] as? String, let pictures = CreditPacks.pictures[product],
            payload["bundleId"] as? String == "com.jsayram.niftyoutfitnook", payload["type"] as? String == "Consumable"
        else { throw .rejected }
        let answer = state.withLock { state -> (CreditClaim, lost: Bool)? in
            state.claims += 1
            if state.offline { return nil }
            let replayed = state.grants[id] != nil
            state.grants[id] = pictures
            let lost = state.loseNextAnswer
            state.loseNextAnswer = false
            return (
                CreditClaim(
                    transactionID: id, pictures: pictures, replayed: replayed,
                    balance: state.grants.values.reduce(0, +)), lost
            )
        }
        guard let answer else { throw .offline }
        if answer.lost { throw .offline }
        return answer.0
    }

    static func payload(_ jws: String) -> [String: Any]? {
        let parts = jws.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacing("-", with: "+").replacing("_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: String(base64)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private final class CreditsBundleMarker {}
