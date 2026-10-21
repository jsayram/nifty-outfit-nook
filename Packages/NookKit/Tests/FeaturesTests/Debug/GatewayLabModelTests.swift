import Foundation
import Models
import Synchronization
import Testing

@testable import Features

/// The Phase 24a gateway screen's model, on a scripted account service.
@MainActor
struct GatewayLabModelTests {
    final class ScriptedAccount: AccountService {
        let next = Mutex<AccountProblem?>(nil)
        let signedIn = Mutex(false)
        let user = AccountUser(id: "usr_0123456789abcdef0123456789abcdef", createdAt: Date(timeIntervalSince1970: 0))
        var providerKind: AuthProviderKind { .fake }
        func isSignedIn() async -> Bool { signedIn.withLock { $0 } }
        func signIn() async throws(AccountProblem) -> AccountUser {
            if let problem = next.withLock({ $0 }) { throw problem }
            signedIn.withLock { $0 = true }
            return user
        }
        func whoAmI() async throws(AccountProblem) -> AccountUser {
            if let problem = next.withLock({ $0 }) { throw problem }
            return user
        }
        func signOut() async { signedIn.withLock { $0 = false } }
    }

    @Test func signInThenWhoAmIShowsTheAccount() async {
        let account = ScriptedAccount()
        let model = GatewayLabModel(account: account, controls: nil)
        await model.refreshStatus()
        #expect(model.status == .signedOut)
        await model.signIn()
        #expect(model.status == .signedIn(account.user))
        await model.whoAmI()
        #expect(model.message == "The backend says you're \(account.user.id).")
        #expect(!model.messageIsProblem)
    }

    @Test func aRateLimitSaysWhenAndHoldsWhoAmI() async {
        let account = ScriptedAccount()
        let now = Date(timeIntervalSince1970: 1000)
        let model = GatewayLabModel(account: account, controls: nil, now: { now })
        account.next.withLock { $0 = .rateLimited(retryAfterSeconds: 30) }
        await model.whoAmI()
        #expect(model.message == "Too many tries. Try again in 30 seconds.")
        #expect(model.messageIsProblem)
        #expect(model.isWaitingToRetry)
        #expect(model.retryAllowedAt == now.addingTimeInterval(30))
    }

    @Test func signedOutFromTheBackendUpdatesTheStatus() async {
        let account = ScriptedAccount()
        let model = GatewayLabModel(account: account, controls: nil)
        await model.signIn()
        account.next.withLock { $0 = .signedOut }
        await model.whoAmI()
        #expect(model.status == .signedOut)
    }

    @Test func cancellingSignInShowsNothing() async {
        let account = ScriptedAccount()
        let model = GatewayLabModel(account: account, controls: nil)
        account.next.withLock { $0 = .cancelled }
        await model.signIn()
        #expect(model.message == nil)
    }

    @Test(arguments: [
        (
            AccountProblem.offline,
            "You're offline. Your closet still works on this iPhone. Try again when you're connected."
        ),
        (.timedOut, "The server took too long to answer. Try again in a moment."),
        (.unavailable(retryAfterSeconds: 600), "This isn't available right now. Try again in 10 minutes."),
        (.unavailable(retryAfterSeconds: nil), "This isn't available right now. Try again later."),
        (.forbidden, "This account can't do that."),
        (.serverError, "Something went wrong on our side. Try again later."),
        (.updateRequired, "Update the app to keep using this."),
        (.invalidResponse, "Something went wrong. Try again later."),
        (.rateLimited(retryAfterSeconds: 1), "Too many tries. Try again in 1 second."),
    ])
    func everyProblemHasPlainWords(problem: AccountProblem, words: String) {
        #expect(GatewayLabModel.message(for: problem) == words)
    }

    @Test func theModeGoesToTheControls() {
        let chosen = Mutex<String?>(nil)
        let controls = GatewayLabControls(modes: [.init(id: "offline", title: "Offline")]) { id in
            chosen.withLock { $0 = id }
        }
        let model = GatewayLabModel(account: ScriptedAccount(), controls: controls)
        model.setMode("offline")
        #expect(model.modeID == "offline")
        #expect(chosen.withLock { $0 } == "offline")
    }

    @Test func theLogKeepsEachCallsOwnLines() {
        let log = GatewayLabLog()
        log.append("old")
        let start = log.total
        log.append("→ me")
        log.append("← me 200")
        #expect(log.lines(since: start) == ["→ me", "← me 200"])
        for index in 0..<100 { log.append("line \(index)") }
        #expect(log.lines.count == 60)
        #expect(log.lines(since: log.total - 2) == ["line 98", "line 99"])
    }
}
