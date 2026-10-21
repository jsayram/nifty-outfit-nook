import Foundation

// Delete my account (Phase 24c, App Review Guideline 5.1.1(v), THREAT_MODEL F12).
//
// The order is chosen so she's never left half-deleted without knowing it:
// 1. Apple confirms it's her and the backend accepts the deletion. If either fails, nothing is
//    deleted anywhere, and the screen says why.
// 2. The backend's steps are read back, a few times if they're still running.
// 3. Her iCloud copy is deleted (decision 0004 §6; sync isn't built yet, so this is a hook).
// 4. Everything on this iPhone is erased, as Delete my data does.
// 5. She's signed out and this iPhone's App Attest key is forgotten.
// Repeating it after a local part failed skips step 1: the backend already has the deletion.

/// Her private iCloud copy, for Delete my account and Delete my data. Sync isn't built yet
/// (decision 0004), so the app uses `NoICloudCopy`; Phase 21b's sync engine conforms to this.
public protocol ICloudCopyDeletion: Sendable {
    /// Whether sync was ever on, so there may be a copy to delete. When false, the part isn't listed.
    var mayHaveCopy: Bool { get }
    /// Deletes the `Closet` and `Me` zones. `pending` when iCloud can't be reached: 0004 §6 runs it
    /// again at the next launch with a connection, before anything can sync.
    func deleteCopy() async -> DeletionOutcome
}

/// No sync, so no copy: what the app uses until sync is built.
public struct NoICloudCopy: ICloudCopyDeletion {
    public init() {}
    public var mayHaveCopy: Bool { false }
    public func deleteCopy() async -> DeletionOutcome { .deleted }
}

/// Delete my data on this iPhone (`thisDevice`, through `local`), and Delete my account
/// (`account`), which adds the backend, the Apple sign-in link and her iCloud copy.
public actor AccountDataDeletion: DataDeletionService {
    private let local: any DataDeletionService
    private let account: any AccountService
    private let iCloud: any ICloudCopyDeletion
    private let polls: Int
    private let pollDelay: Duration
    /// The backend's deletion, once it accepted one, so trying again doesn't ask Apple again.
    private var accepted: AccountDeletion?

    /// - Parameters:
    ///   - polls: how many times to read the backend's progress while it's still running.
    ///   - pollDelay: how long to wait between those reads.
    public init(
        local: any DataDeletionService, account: any AccountService, iCloud: any ICloudCopyDeletion = NoICloudCopy(),
        polls: Int = 3, pollDelay: Duration = .seconds(1)
    ) {
        self.local = local
        self.account = account
        self.iCloud = iCloud
        self.polls = polls
        self.pollDelay = pollDelay
    }

    public nonisolated var scopes: [DeletionScope] { local.scopes + [.account] }

    public nonisolated func parts(in scope: DeletionScope) -> [DataPart] {
        let onDevice = local.parts(in: .thisDevice)
        switch scope {
        case .thisDevice: return onDevice
        case .account:
            var remote: [DataPart] = [.serverData, .account, .signInWithApple]
            if iCloud.mayHaveCopy { remote.append(.iCloudCopy) }
            return remote + onDevice
        }
    }

    public func delete(_ scope: DeletionScope) async -> DeletionReport {
        guard scope == .account else { return await local.delete(scope) }

        var deletion: AccountDeletion
        if let accepted {
            deletion = accepted
        } else {
            do {
                deletion = try await account.deleteAccount()
            } catch {
                return DeletionReport(scope: scope, results: [], notStarted: Self.notStarted(error))
            }
        }
        // Read the backend's progress while it's still working. If it can't be read, the last
        // answer stands: the backend finishes on its own either way.
        var reads = 0
        while !deletion.isComplete, deletion.steps.values.contains(.pending), reads < polls {
            reads += 1
            try? await Task.sleep(for: pollDelay)
            if let fresh = try? await account.accountDeletion(id: deletion.id) { deletion = fresh }
        }
        accepted = deletion

        var results: [(DataPart, DeletionOutcome)] = [
            (.serverData, Self.outcome(deletion.steps[.serverData])),
            (.account, Self.outcome(deletion.steps[.account])),
            (.signInWithApple, Self.outcome(deletion.steps[.signInWithApple])),
        ]
        if iCloud.mayHaveCopy { results.append((.iCloudCopy, await iCloud.deleteCopy())) }
        let onDevice = await local.delete(.thisDevice)
        results += onDevice.order.map { ($0, onDevice.outcomes[$0] ?? .failed) }
        // Signed out either way: the account is going, and its session with it.
        await account.forgetAccountOnThisDevice()
        return DeletionReport(scope: scope, results: results)
    }

    static func outcome(_ state: AccountDeletion.State?) -> DeletionOutcome {
        switch state {
        case .done: .deleted
        case .pending, nil: .pending
        case .failed: .failed
        }
    }

    static func notStarted(_ problem: AccountProblem) -> DeletionNotStarted {
        switch problem {
        case .cancelled: .cancelled
        case .offline, .timedOut: .offline
        case .signedOut, .forbidden: .signedOut
        case .rateLimited(let seconds): .unavailable(retryAfterSeconds: seconds)
        case .unavailable(let seconds): .unavailable(retryAfterSeconds: seconds)
        case .serverError, .updateRequired, .invalidResponse, .rejected: .unavailable(retryAfterSeconds: nil)
        }
    }
}
