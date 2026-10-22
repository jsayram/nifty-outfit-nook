import Foundation
import Models
import Observation

/// Delete my data (Phase 14b, PRD §15.4, SECURITY_STANDARD §9), and Delete my account (Phase
/// 24c, App Review Guideline 5.1.1(v)), which also deletes what the backend keeps for her.
///
/// The screen first says what will go, with live counts, then asks once more, then deletes every
/// part through `DataDeletionService` and reports part by part. When everything is gone the app
/// starts fresh (`DataDeletedAction`); when a part couldn't be deleted, the screen says which and
/// offers Try again, which deletes again (deleting is safe to repeat).
@Observable
final class DeleteDataModel {
    enum Phase: Equatable {
        case ready
        case deleting
        /// Something wasn't deleted. A complete deletion doesn't stay here: the app starts fresh.
        case incomplete(DeletionReport)
        /// Delete my account didn't start, so nothing was deleted (24c). Closing Apple's sheet
        /// goes back to `ready` instead.
        case notStarted(DeletionNotStarted)
        /// Delete my account: everything on this iPhone is gone, but the backend is still
        /// finishing, or the Apple link needs her (24c). Done starts the app fresh.
        case finished(DeletionReport)
    }

    /// How much there is, for the list. Read before she decides.
    struct Counts: Hashable {
        var pieces = 0
        var looks = 0
        var pictures = 0
        var suitcases = 0
        var drafts = 0
    }

    private(set) var phase: Phase = .ready
    /// `nil` until read, or when a store couldn't be read: the list then shows without numbers.
    private(set) var counts: Counts?
    /// What the deletion covers, from the service, in reading order (closet first).
    private(set) var parts: [DataPart]
    /// 30a: Delete my account, while she has a subscription that may still bill her: the note
    /// that deleting doesn't cancel it, and Manage subscription.
    private(set) var subscriptionMayRenew = false
    /// The subscription group, for Apple's Manage subscription sheet.
    private(set) var subscriptionGroupID: String?
    @ObservationIgnored private var loads = LoadGeneration()
    let scope: DeletionScope

    init(scope: DeletionScope = .thisDevice) {
        self.scope = scope
        // Until `load` asks the service: what's held elsewhere first, then this iPhone. The iCloud
        // copy is listed only when the service says sync was on.
        let local = DataPart.allCases.filter { !$0.isRemote }
        parts = scope == .account ? [.serverData, .account, .signInWithApple] + local : local
    }

    func load(from services: NookServices) async {
        let covered = services.deletion.parts(in: scope)
        // What's held elsewhere first, in the service's order, then this iPhone, closet first.
        parts = covered.filter(\.isRemote) + DataPart.allCases.filter { !$0.isRemote && covered.contains($0) }
        let load = loads.begin()
        if scope == .account {
            // StoreKit's own records on the phone, so this works offline and signed out of the App
            // Store too. A refresh failing leaves the cached status.
            let subscriptions = services.subscriptions
            subscriptionMayRenew = await subscriptions.refresh().mayRenew
            subscriptionGroupID = await subscriptions.subscriptionGroupID()
        }
        do {
            var counts = Counts()
            counts.pieces = try await services.closet.garments().count
            counts.looks = try await services.looks.looks().count
            counts.pictures = try await services.pictures.pictures().count
            counts.suitcases = try await services.suitcases.suitcases().count
            counts.drafts = try await services.drafts.drafts().count
            if try await services.lookDrafts.draft() != nil { counts.drafts += 1 }
            if try await services.feedbackDrafts.draft() != nil { counts.drafts += 1 }
            guard loads.isCurrent(load) else { return }
            self.counts = counts
        } catch {
            guard loads.isCurrent(load) else { return }
            counts = nil
        }
    }

    /// Sets the counts directly, for snapshot tests.
    func show(_ counts: Counts?, phase: Phase = .ready, subscriptionMayRenew: Bool = false) {
        self.counts = counts
        self.phase = phase
        self.subscriptionMayRenew = subscriptionMayRenew
    }

    /// Deletes everything in scope. Returns true when every part was deleted.
    /// - Parameter signIn: Release: Delete my account needs her signed in. If the session has
    ///   ended, the sign-in sheet asks first (and once more if the server says she's signed out);
    ///   Not now deletes nothing.
    func delete(in services: NookServices, signIn: SignInCheck = .notNeeded) async -> Bool {
        guard phase != .deleting else { return false }
        if scope == .account {
            guard await signIn(.deleteAccount) else { return false }
        }
        guard phase != .deleting else { return false }
        phase = .deleting
        var report = await services.deletion.delete(scope)
        if scope == .account, report.notStarted == .signedOut, signIn.isInstalled, await signIn(.deleteAccount) {
            report = await services.deletion.delete(scope)
        }
        if let reason = report.notStarted {
            phase = reason == .cancelled ? .ready : .notStarted(reason)
            return false
        }
        if report.isComplete {
            phase = .ready
            return true
        }
        phase = report.isLocalComplete ? .finished(report) : .incomplete(report)
        return false
    }
}
