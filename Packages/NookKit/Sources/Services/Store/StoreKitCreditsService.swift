import Foundation
import Models
import StoreKit
import Synchronization
import UIKit

/// Picture packs through StoreKit 2 (Phase 30b): consumables that the server credits.
///
/// - A purchase sends the transaction's signed JWS to the server (`CreditClaiming`, POST
///   /v1/credits/claim) and finishes the transaction only after the server says it's credited.
///   If the server can't be reached the transaction stays unfinished, so the purchase isn't lost.
/// - `recoverUnfinished()` runs at launch: StoreKit keeps every unfinished consumable in
///   `Transaction.unfinished` (consumables never appear in `Transaction.currentEntitlements`), and
///   each one is claimed again. The server credits a transaction once, so a second claim of the
///   same purchase adds nothing.
/// - `start()` listens to `Transaction.updates` for packs that arrive later (an approved Ask to
///   Buy, a purchase on another device). `StoreKitSubscriptionService`'s listener leaves
///   consumables alone for this one.
/// - An unverified transaction is never sent or finished: it waits, and the server (which checks
///   Apple's signature itself from 30c) is the one that decides.
public final class StoreKitCreditsService: CreditsService {
    private let productIDs: Set<String>
    private let claimer: any CreditClaiming
    /// 30c: the account token purchases carry, so Apple's notification names the account.
    private let purchaseToken: PurchaseAccountToken
    /// Where recovery finds packs paid for but not credited: `Transaction.unfinished` in the app. Tests
    /// pass their own, because Xcode's StoreKit test environment drops an unfinished consumable
    /// from `Transaction.unfinished` about a second after it first lists it (30b, iOS 26.5
    /// simulator), with no `finish()` from the app.
    private let unfinished: @Sendable () async -> [VerificationResult<Transaction>]
    private let state = Mutex(State())

    private struct State {
        var products: [Product] = []
        var listener: Task<Void, Never>?
        var streams: [UUID: AsyncStream<Int>.Continuation] = [:]
    }

    public init(
        productIDs: Set<String> = CreditPacks.all, claimer: any CreditClaiming,
        purchaseToken: PurchaseAccountToken = .shared,
        unfinished: @escaping @Sendable () async -> [VerificationResult<Transaction>] = {
            await StoreKitCreditsService.allUnfinished()
        }
    ) {
        self.productIDs = productIDs
        self.claimer = claimer
        self.purchaseToken = purchaseToken
        self.unfinished = unfinished
    }

    /// Every unfinished transaction StoreKit has for the app.
    public static func allUnfinished() async -> [VerificationResult<Transaction>] {
        var found: [VerificationResult<Transaction>] = []
        for await result in Transaction.unfinished { found.append(result) }
        return found
    }

    deinit {
        state.withLock { $0.listener?.cancel() }
    }

    /// Starts listening to `Transaction.updates` for packs. Call once, at launch. Calling again
    /// does nothing.
    public func start() {
        state.withLock { state in
            guard state.listener == nil else { return }
            // The iterator is made here, not inside the task, so an update that arrives before a
            // late-starting task begins to iterate isn't missed (see StoreKitSubscriptionService).
            nonisolated(unsafe) var updates = Transaction.updates.makeAsyncIterator()
            state.listener = Task.detached(priority: .utility) { [weak self] in
                while let update = await updates.next() {
                    guard let self, self.productIDs.contains(update.unsafePayloadValue.productID) else { continue }
                    _ = await self.credit(update)
                }
            }
        }
    }

    /// Stops listening and ends every balance stream. For tests.
    public func stop() {
        let streams = state.withLock { state in
            state.listener?.cancel()
            state.listener = nil
            defer { state.streams = [:] }
            return Array(state.streams.values)
        }
        for stream in streams { stream.finish() }
    }

    // MARK: CreditsService

    public func packs() async throws(SubscriptionProblem) -> [CreditPackOffer] {
        do {
            return try await products().map { product in
                CreditPackOffer(
                    productID: product.id, displayName: product.displayName, displayPrice: product.displayPrice,
                    pictures: CreditPacks.pictures[product.id] ?? 0)
            }
        } catch {
            throw StoreKitSubscriptionService.problem(for: error)
        }
    }

    public func purchase(_ productID: String) async -> CreditPurchaseOutcome {
        let product: Product
        do {
            guard let found = try await products().first(where: { $0.id == productID }) else {
                return .failed(.unavailable)
            }
            product = found
        } catch {
            return .failed(StoreKitSubscriptionService.problem(for: error))
        }
        let result: Product.PurchaseResult
        do {
            result = try await StoreKitSubscriptionService.buy(
                product, options: StoreKitSubscriptionService.purchaseOptions(token: purchaseToken.current))
        } catch {
            return .failed(StoreKitSubscriptionService.problem(for: error))
        }
        switch result {
        case .success(let verification):
            switch await credit(verification) {
            case .credited(let claim): return .credited(pictures: claim.pictures, balance: claim.balance)
            case .notYet: return .awaitingCredit
            case .unverified: return .failed(.unverified)
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .failed(.failed)
        }
    }

    public func recoverUnfinished() async -> Int {
        var credited = 0
        for result in await unfinished() {
            guard productIDs.contains(result.unsafePayloadValue.productID) else { continue }
            if case .credited(let claim) = await credit(result), !claim.replayed { credited += 1 }
        }
        return credited
    }

    public func balanceUpdates() async -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        let id = UUID()
        state.withLock { $0.streams[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.streams.removeValue(forKey: id) }
        }
        return stream
    }

    // MARK: Crediting

    enum Credit: Equatable {
        case credited(CreditClaim)
        /// Not credited yet; the transaction stays unfinished to try again.
        case notYet
        case unverified
    }

    /// Has the server credit one pack's transaction, then finishes it. It stays unfinished unless
    /// the server confirmed it (PRD 14.4: the grant is kept before delivery is finished).
    func credit(_ verification: VerificationResult<Transaction>) async -> Credit {
        guard case .verified(let transaction) = verification else { return .unverified }
        // Refunded before it was credited: nothing to credit, and nothing to keep open.
        if transaction.revocationDate != nil {
            await transaction.finish()
            return .notYet
        }
        do {
            let claim = try await claimer.claim(signedTransaction: verification.jwsRepresentation)
            await transaction.finish()
            broadcast(claim.balance)
            return .credited(claim)
        } catch {
            // Not credited, whatever the reason (offline, signed out, the server refused it): the
            // transaction stays open, so a paid pack is never dropped. Recovery tries it again at
            // the next launch; the server credits it once.
            return .notYet
        }
    }

    private func products() async throws -> [Product] {
        let cached = state.withLock { $0.products }
        if !cached.isEmpty { return cached }
        let products = try await Product.products(for: productIDs)
            .sorted { (CreditPacks.pictures[$0.id] ?? 0) < (CreditPacks.pictures[$1.id] ?? 0) }
        guard !products.isEmpty else { throw SubscriptionProblem.unavailable }
        state.withLock { $0.products = products }
        return products
    }

    private func broadcast(_ balance: Int) {
        let streams = state.withLock { Array($0.streams.values) }
        for stream in streams { stream.yield(balance) }
    }
}
