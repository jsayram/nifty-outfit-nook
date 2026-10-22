import Foundation
import Models
import NookTestSupport
import Testing

@testable import Networking

/// Delete my account (Phase 24c) through the real client and the fake backend: Apple is asked
/// first, the backend deletes everything it holds and ends the sign-in, a failure part-way is
/// finished by a retry, and the status can be read without a sign-in.
@Suite("Account deletion")
struct AccountDeletionGatewayTests {
    let backend = FakeBackend()
    let auth = FakeAuthProvider(subject: "lily")
    let policy = RetryPolicy(requestTimeout: .seconds(60))
    /// The client's clock, which a wait between retries jumps ahead on instead of really waiting,
    /// so these tests neither take real seconds nor have a timeout that a slow machine could hit.
    let clock = ManualClock()

    func client(auth: (any AuthProvider)? = nil) -> APIClient {
        let clock = clock
        return APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth ?? self.auth, policy: policy, clock: clock, sleep: { try await clock.skip($0) })
    }

    /// Signed in, with a paid action and a registered key on the backend.
    func signedIn() async throws -> (GatewayAccountService, AttestationSession, MemoryAttestKeyStore) {
        let client = client()
        let store = MemoryAttestKeyStore()
        let attestation = AttestationSession(attester: FakeDeviceAttester(), store: store, client: client)
        let account = GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0", attestation: attestation)
        _ = try await account.signIn()
        let paid = GatewayPaidActionService(client: client, attestation: attestation)
        _ = try await paid.run(.style(mode: .full, contextRevision: "rev_1"), idempotencyKey: IdempotencyKey.make())
        #expect(backend.holdsData(forSubject: "lily"))
        #expect(store.load() != nil)
        return (account, attestation, store)
    }

    @Test func deletingRemovesEverythingTheBackendHoldsAndEndsTheSignIn() async throws {
        let (account, _, store) = try await signedIn()
        let deletion = try await account.deleteAccount()
        #expect(deletion.isComplete)
        #expect(deletion.id.wholeMatch(of: /del_[0-9a-f]{32}/) != nil)
        #expect(deletion.steps == [.signInWithApple: .done, .serverData: .done, .account: .done])
        #expect(!backend.holdsData(forSubject: "lily"))
        #expect(backend.accountDeletionsCompleted == 1)

        await account.forgetAccountOnThisDevice()
        #expect(await !auth.isSignedIn())
        #expect(store.load() == nil)
        // Signing in again with the same pretend Apple user: its old tokens are gone, as at Clerk.
        try await auth.signInWithApple()
        await #expect(throws: AccountProblem.signedOut) { try await account.whoAmI() }
        // The status needs no sign-in.
        let status = try await GatewayAccountService(
            auth: FakeAuthProvider(), client: client(auth: FakeAuthProvider()), appVersion: "0.1.0"
        )
        .accountDeletion(id: deletion.id)
        #expect(status == deletion)
    }

    @Test func aRetryFinishesADeletionThatFailedPartWay() async throws {
        let (account, _, _) = try await signedIn()
        backend.failAccountDeletion(times: 1)
        let first = try await account.deleteAccount()
        #expect(!first.isComplete)
        #expect(first.steps[.serverData] == .done)
        #expect(first.steps[.account] == .pending)
        // While it runs, everything else is refused.
        await #expect(throws: AccountProblem.forbidden) { try await account.whoAmI() }
        let second = try await account.deleteAccount()
        #expect(second.id == first.id)
        #expect(second.isComplete)
        #expect(backend.accountDeletionsCompleted == 1)
        let status = try await account.accountDeletion(id: first.id)
        #expect(status.isComplete)
    }

    @Test func closingApplesSheetSendsNothing() async throws {
        let (account, _, _) = try await signedIn()
        let before = backend.requestCount
        await auth.failNextSignIn(with: .cancelled)
        await #expect(throws: AccountProblem.cancelled) { try await account.deleteAccount() }
        #expect(backend.requestCount == before)
        #expect(backend.holdsData(forSubject: "lily"))
    }

    @Test func offlineAndUnknownDeletionsAreReportedAsSuch() async throws {
        let (account, _, _) = try await signedIn()
        backend.setMode(.offline, times: 1)
        await #expect(throws: AccountProblem.offline) { try await account.deleteAccount() }
        #expect(backend.holdsData(forSubject: "lily"))
        await #expect(throws: AccountProblem.self) {
            try await account.accountDeletion(id: "del_0123456789abcdef0123456789abcdef")
        }
    }

    @Test func aRefusedAppleCodeIsReportedAndTheRestFinishes() async throws {
        // The fake's stand-in for Apple refusing the code, as the real backend's mock does.
        let deletion = GatewayAccountService.deletion(
            .init(
                id: "del_0123456789abcdef0123456789abcdef", state: "completed", requestedAt: .init(Date()),
                completedAt: .init(Date()),
                steps: [
                    .init(step: "signInWithApple", state: "failed"), .init(step: "serverData", state: "done"),
                    .init(step: "account", state: "done"), .init(step: "somethingNew", state: "done"),
                ]))
        #expect(deletion.isComplete)
        #expect(deletion.steps == [.signInWithApple: .failed, .serverData: .done, .account: .done])
        // A state this app doesn't know is never shown as done.
        let unknown = GatewayAccountService.deletion(
            .init(
                id: "del_x", state: "in_progress", requestedAt: .init(Date()), completedAt: nil,
                steps: [.init(step: "account", state: "queued")]))
        #expect(unknown.steps[.account] == .pending)
    }
}
