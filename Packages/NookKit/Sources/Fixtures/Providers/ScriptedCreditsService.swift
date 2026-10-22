import Foundation
import Models
import Synchronization

/// Picture packs that follow a script, for model and snapshot tests and debug launches (30b).
/// Nothing is bought: a purchase moves to the scripted outcome and adds to the balance.
public final class ScriptedCreditsService: CreditsService {
    private struct State {
        var packs: [CreditPackOffer]
        var balance: Int
        /// Nil credits the pack.
        var outcome: CreditPurchaseOutcome?
        var streams: [UUID: AsyncStream<Int>.Continuation] = [:]
        var purchases: [String] = []
        var unfinished: [String] = []
    }

    private let state: Mutex<State>

    public init(
        packs: [CreditPackOffer] = CreditPackOffer.samples, balance: Int = 0, outcome: CreditPurchaseOutcome? = nil
    ) {
        state = Mutex(State(packs: packs, balance: balance, outcome: outcome))
    }

    /// The products bought, in order.
    public var purchases: [String] { state.withLock { $0.purchases } }
    public var balance: Int { state.withLock { $0.balance } }

    /// A pack that was paid for but not credited, for `recoverUnfinished()` to find.
    public func leaveUnfinished(_ productID: String) {
        state.withLock { $0.unfinished.append(productID) }
    }

    public func packs() async throws(SubscriptionProblem) -> [CreditPackOffer] {
        let packs = state.withLock { $0.packs }
        if packs.isEmpty { throw .unavailable }
        return packs
    }

    public func purchase(_ productID: String) async -> CreditPurchaseOutcome {
        let (outcome, balance) = state.withLock { state -> (CreditPurchaseOutcome, Int?) in
            state.purchases.append(productID)
            if let scripted = state.outcome { return (scripted, nil) }
            let pictures = state.packs.first { $0.productID == productID }?.pictures ?? 0
            state.balance += pictures
            return (.credited(pictures: pictures, balance: state.balance), state.balance)
        }
        if let balance { broadcast(balance) }
        return outcome
    }

    public func recoverUnfinished() async -> Int {
        let (count, balance) = state.withLock { state -> (Int, Int) in
            let found = state.unfinished
            state.unfinished = []
            for id in found { state.balance += state.packs.first { $0.productID == id }?.pictures ?? 0 }
            return (found.count, state.balance)
        }
        if count > 0 { broadcast(balance) }
        return count
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

    private func broadcast(_ balance: Int) {
        let streams = state.withLock { Array($0.streams.values) }
        for stream in streams { stream.yield(balance) }
    }
}

extension CreditPackOffer {
    /// The local StoreKit configuration's PLACEHOLDER packs.
    public static let samples = [
        CreditPackOffer(
            productID: CreditPacks.small, displayName: "10 try-on pictures", displayPrice: "$2.99", pictures: 10),
        CreditPackOffer(
            productID: CreditPacks.large, displayName: "30 try-on pictures", displayPrice: "$6.99", pictures: 30),
    ]
}
