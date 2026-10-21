import Foundation
import Models
import Synchronization
import Testing

@testable import Features

/// The Phase 24b limits screen's model, on a scripted paid service.
@MainActor
struct LimitsLabModelTests {
    final class ScriptedPaid: PaidActionService {
        let next = Mutex<CloudLimitProblem?>(nil)
        let keys = Mutex<[String]>([])
        func usage() async throws(CloudLimitProblem) -> CloudUsage {
            CloudUsage(
                allowances: [
                    .init(
                        category: .tryOn, usedToday: 1, limitToday: 3, usedThisMonth: 1, limitThisMonth: 30,
                        resetsAt: nil)
                ],
                paused: [])
        }
        func run(_ request: PaidActionRequest, idempotencyKey: String) async throws(CloudLimitProblem)
            -> PaidActionReceipt
        {
            if let problem = next.withLock({ $0 }) { throw problem }
            let seen = keys.withLock { keys -> Bool in
                defer { keys.append(idempotencyKey) }
                return keys.contains(idempotencyKey)
            }
            return PaidActionReceipt(
                id: "act_1", feature: request.feature, replayed: seen,
                usage: .init(
                    category: request.category, usedToday: 1, limitToday: 3, usedThisMonth: 1, limitThisMonth: 30,
                    resetsAt: nil))
        }
    }

    final class SignedIn: AccountService {
        var providerKind: AuthProviderKind { .fake }
        func isSignedIn() async -> Bool { true }
        func signIn() async throws(AccountProblem) -> AccountUser { AccountUser(id: "usr_x", createdAt: Date()) }
        func whoAmI() async throws(AccountProblem) -> AccountUser { AccountUser(id: "usr_x", createdAt: Date()) }
        func signOut() async {}
    }

    @Test func sendingAgainUsesTheSameKeyAndSaysItWasntCountedTwice() async {
        let paid = ScriptedPaid()
        let model = LimitsLabModel(account: SignedIn(), paid: paid, controls: nil)
        await model.start()
        #expect(model.usage?.allowance(.tryOn)?.remainingToday == 2)
        await model.run(.tryOn(contextRevision: "r"))
        #expect(model.message == "Done: a try-on picture (placeholder).")
        #expect(model.detail == "Run and counted once.")
        await model.sendAgain()
        #expect(model.detail == "The server had already done this one, so it wasn't run or counted again.")
        let keys = paid.keys.withLock { $0 }
        #expect(keys.count == 2 && keys[0] == keys[1])
        // A new action gets a new key.
        await model.run(.tryOn(contextRevision: "r"))
        #expect(paid.keys.withLock { Set($0).count } == 2)
    }

    @Test func aLimitShowsItsMessage() async {
        let paid = ScriptedPaid()
        let model = LimitsLabModel(account: SignedIn(), paid: paid, controls: nil)
        paid.next.withLock { $0 = .paused(feature: .tryOn, retryAfterSeconds: nil) }
        await model.run(.tryOn(contextRevision: "r"))
        #expect(model.messageIsProblem)
        #expect(model.message == CloudLimitText.message(for: .paused(feature: .tryOn, retryAfterSeconds: nil)))
        #expect(model.detail == nil)
    }
}
