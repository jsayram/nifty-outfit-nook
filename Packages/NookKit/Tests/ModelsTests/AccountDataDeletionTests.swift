import Foundation
import Models
import Synchronization
import Testing

/// Delete my account (Phase 24c): nothing is deleted until Apple and the backend agree, the
/// backend's steps are reported honestly, everything on the iPhone goes, she's signed out, and
/// trying again after a local failure doesn't ask the backend twice.
struct AccountDataDeletionTests {
    /// The backend as a script: what `deleteAccount` answers, then what each status read answers.
    final class ScriptedAccount: AccountService {
        struct State {
            var deleteAnswer: Result<AccountDeletion, AccountProblem>
            var statusAnswers: [AccountDeletion] = []
            var deleteCalls = 0
            var statusCalls = 0
            var forgotten = 0
        }
        let state: Mutex<State>

        init(_ answer: Result<AccountDeletion, AccountProblem>, then statuses: [AccountDeletion] = []) {
            state = Mutex(State(deleteAnswer: answer, statusAnswers: statuses))
        }

        var providerKind: AuthProviderKind { .fake }
        func isSignedIn() async -> Bool { true }
        func signIn() async throws(AccountProblem) -> AccountUser { throw .signedOut }
        func whoAmI() async throws(AccountProblem) -> AccountUser { throw .signedOut }
        func signOut() async {}
        func deleteAccount() async throws(AccountProblem) -> AccountDeletion {
            let answer = state.withLock {
                $0.deleteCalls += 1
                return $0.deleteAnswer
            }
            return try answer.get()
        }
        func accountDeletion(id: String) async throws(AccountProblem) -> AccountDeletion {
            let next = state.withLock { state -> AccountDeletion? in
                state.statusCalls += 1
                return state.statusAnswers.isEmpty ? nil : state.statusAnswers.removeFirst()
            }
            guard let next else { throw .offline }
            return next
        }
        func forgetAccountOnThisDevice() async { state.withLock { $0.forgotten += 1 } }
    }

    /// This iPhone's stores as one fake: records erases and can fail once.
    final class FakeLocal: DataDeletionService {
        let erases = Mutex(0)
        let failsNext: Mutex<Bool>
        init(fails: Bool = false) { failsNext = Mutex(fails) }
        var scopes: [DeletionScope] { [.thisDevice] }
        func parts(in scope: DeletionScope) -> [DataPart] { [.drafts, .closet, .profile] }
        func delete(_ scope: DeletionScope) async -> DeletionReport {
            erases.withLock { $0 += 1 }
            let fails = failsNext.withLock { value in
                defer { value = false }
                return value
            }
            return DeletionReport(
                scope: scope,
                results: [(.drafts, .deleted), (.closet, fails ? .failed : .deleted), (.profile, .deleted)])
        }
    }

    final class FakeICloud: ICloudCopyDeletion {
        let mayHaveCopy = true
        let outcome: DeletionOutcome
        let calls = Mutex(0)
        init(outcome: DeletionOutcome) { self.outcome = outcome }
        func deleteCopy() async -> DeletionOutcome {
            calls.withLock { $0 += 1 }
            return outcome
        }
    }

    static func deletion(
        _ apple: AccountDeletion.State = .done, server: AccountDeletion.State = .done,
        account: AccountDeletion.State = .done
    ) -> AccountDeletion {
        AccountDeletion(
            id: "del_0123456789abcdef0123456789abcdef", isComplete: server == .done && account == .done,
            steps: [.signInWithApple: apple, .serverData: server, .account: account])
    }

    private func make(
        _ account: ScriptedAccount, local: FakeLocal = FakeLocal(), iCloud: any ICloudCopyDeletion = NoICloudCopy()
    )
        -> AccountDataDeletion
    {
        AccountDataDeletion(local: local, account: account, iCloud: iCloud, polls: 2, pollDelay: .zero)
    }

    @Test func aFinishedDeletionErasesTheIPhoneSignsOutAndReportsEveryPart() async {
        let account = ScriptedAccount(.success(Self.deletion()))
        let local = FakeLocal()
        let report = await make(account, local: local).delete(.account)
        #expect(report.isComplete)
        #expect(report.order == [.serverData, .account, .signInWithApple, .drafts, .closet, .profile])
        #expect(local.erases.withLock { $0 } == 1)
        #expect(account.state.withLock { $0.forgotten } == 1)
    }

    @Test(arguments: [
        (AccountProblem.cancelled, DeletionNotStarted.cancelled),
        (.offline, .offline),
        (.timedOut, .offline),
        (.signedOut, .signedOut),
        (.unavailable(retryAfterSeconds: 30), .unavailable(retryAfterSeconds: 30)),
        (.serverError, .unavailable(retryAfterSeconds: nil)),
    ])
    func whenAppleOrTheBackendSaysNoNothingIsDeleted(problem: AccountProblem, reason: DeletionNotStarted) async {
        let account = ScriptedAccount(.failure(problem))
        let local = FakeLocal()
        let report = await make(account, local: local).delete(.account)
        #expect(report.notStarted == reason)
        #expect(!report.isComplete)
        #expect(report.order.isEmpty)
        #expect(local.erases.withLock { $0 } == 0)
        #expect(account.state.withLock { $0.forgotten } == 0)
    }

    @Test func aBackendStillWorkingIsReadAgainUntilItFinishes() async {
        let account = ScriptedAccount(
            .success(Self.deletion(account: .pending)), then: [Self.deletion(account: .pending), Self.deletion()])
        let report = await make(account).delete(.account)
        #expect(report.isComplete)
        #expect(account.state.withLock { $0.statusCalls } == 2)
    }

    @Test func aBackendThatHasntFinishedIsReportedAsPendingNotDone() async {
        let account = ScriptedAccount(.success(Self.deletion(.failed, account: .pending)))
        let report = await make(account).delete(.account)
        #expect(!report.isComplete)
        #expect(report.isLocalComplete)
        #expect(report.outcomes[.account] == .pending)
        #expect(report.outcomes[.signInWithApple] == .failed)
        #expect(report.outcomes[.serverData] == .deleted)
        // Signed out anyway: the backend finishes on its own.
        #expect(account.state.withLock { $0.forgotten } == 1)
    }

    @Test func tryingAgainAfterALocalFailureDoesntAskTheBackendAgain() async {
        let account = ScriptedAccount(.success(Self.deletion()))
        let local = FakeLocal(fails: true)
        let deletion = make(account, local: local)
        let first = await deletion.delete(.account)
        #expect(!first.isLocalComplete)
        #expect(first.failedParts == [.closet])
        let second = await deletion.delete(.account)
        #expect(second.isComplete)
        #expect(account.state.withLock { $0.deleteCalls } == 1)
        #expect(local.erases.withLock { $0 } == 2)
    }

    @Test func herICloudCopyIsDeletedWhenSyncWasEverOn() async {
        let iCloud = FakeICloud(outcome: .pending)
        let deletion = make(ScriptedAccount(.success(Self.deletion())), iCloud: iCloud)
        #expect(deletion.parts(in: .account).contains(.iCloudCopy))
        let report = await deletion.delete(.account)
        #expect(iCloud.calls.withLock { $0 } == 1)
        #expect(report.outcomes[.iCloudCopy] == .pending)
        #expect(report.isLocalComplete)

        let never = make(ScriptedAccount(.success(Self.deletion())), iCloud: NoICloudCopy())
        #expect(!never.parts(in: .account).contains(.iCloudCopy))
    }

    @Test func deleteMyDataOnThisIPhoneNeverTouchesTheAccount() async {
        let account = ScriptedAccount(.success(Self.deletion()))
        let deletion = make(account)
        #expect(deletion.parts(in: .thisDevice) == [.drafts, .closet, .profile])
        #expect(deletion.scopes == [.thisDevice, .account])
        let report = await deletion.delete(.thisDevice)
        #expect(report.isComplete)
        #expect(account.state.withLock { $0.deleteCalls } == 0)
        #expect(account.state.withLock { $0.forgotten } == 0)
    }
}
