import Foundation

// Delete my data (Phase 14b, PRD §15.4, SECURITY_STANDARD §9).
//
// Stage A has no account and nothing leaves the phone, so the only scope is the data on this
// iPhone: every store is erased through its protocol. The shape is built for Phase 24c, which adds
// an account and data held on the server: new parts (`account`, `serverData`) whose outcome can be
// `pending` until the server confirms, and new scopes for "only what the developer holds" and
// "everything". Apple requires in-app account deletion once accounts exist (App Review Guideline
// 5.1.1(v)); the entry points already lead here.

/// A store that can forget everything it holds, for Delete my data.
public protocol ErasableStore: Sendable {
    /// Removes everything the store holds, so it reads as on a fresh install. Erasing an empty
    /// store is fine. The real stores (Phase 21a) delete their records from the store on the
    /// iPhone; Phase 22a adds the image files behind them.
    func eraseAll() async throws(StoreError)
}

/// What a deletion covers. PRD §15.4 asks for plainly labelled scopes.
public enum DeletionScope: String, CaseIterable, Hashable, Sendable {
    /// Everything she made in the app, on this iPhone. Stage A's only scope.
    ///
    /// Phase 20b adds her private iCloud copy to it.
    case thisDevice
    /// Delete my account (Phase 24c, App Review Guideline 5.1.1(v)): her account and everything
    /// the backend keeps for it, the Apple sign-in link, her iCloud copy, and everything on this
    /// iPhone. Offered only while she's signed in.
    case account
}

/// One part of her data, deleted as a unit and reported on its own, so a screen can say exactly
/// what was deleted and what wasn't.
public enum DataPart: String, CaseIterable, Hashable, Sendable {
    /// Her pieces, their pictures and details, including Recently deleted.
    case closet
    /// Saved looks, looks she made, and unsaved results kept as history.
    case looks
    /// Try-on pictures.
    case pictures
    case suitcases
    /// The name on her sign, Preferences, fit, measurements, fitting pieces, the try-on photo,
    /// the remembered source and occasion, the tours she has seen with the "Show tips on new
    /// screens" switch (Phase 16a), and that she has finished onboarding, with the closet she
    /// started from (Phase 17). Erased back to a fresh profile, with tips on, and the app opens on
    /// onboarding again.
    case profile
    /// Unsaved Add a piece, Edit and Make your own look work, and the unsent Send feedback note
    /// (Phase 21a).
    case drafts
    // Tour progress is a preference, so it goes with the profile (PRD §7.8: Delete My Data
    // resets it), and so does the onboarding state.

    // Phase 24c, Delete my account only. Each can be `pending` until the backend confirms it.
    /// Everything the backend keeps for her account: usage records, App Attest keys, sign-in
    /// records. Paid work still running is cancelled.
    case serverData
    /// The sign-in account itself, which ends every session.
    case account
    /// The link between her Apple Account and the app (Sign in with Apple). If the backend can't
    /// revoke it, she can remove it in Settings.
    case signInWithApple
    /// Her private iCloud copy (decision 0004 §6). Listed only when sync was ever on.
    case iCloudCopy

    /// The parts held off the iPhone.
    public var isRemote: Bool {
        switch self {
        case .serverData, .account, .signInWithApple, .iCloudCopy: true
        case .closet, .looks, .pictures, .suitcases, .profile, .drafts: false
        }
    }
}

/// Why a deletion didn't start: nothing was deleted.
public enum DeletionNotStarted: Hashable, Sendable {
    /// She closed Apple's sign-in sheet.
    case cancelled
    case offline
    /// Signed out, or the backend refused her sign-in: she needs to sign in again first.
    case signedOut
    /// The backend couldn't take the request now. Try again later, after this many seconds when known.
    case unavailable(retryAfterSeconds: Int?)
}

/// How one part's deletion went.
public enum DeletionOutcome: Hashable, Sendable {
    case deleted
    /// Asked for, not confirmed yet. Only server-held parts can be pending (Phase 24c); local
    /// erasing either works or fails.
    case pending
    case failed
}

/// What a deletion did, part by part, in the order the parts were deleted.
public struct DeletionReport: Hashable, Sendable {
    public var scope: DeletionScope
    public var outcomes: [DataPart: DeletionOutcome]
    /// The parts in the order they were deleted.
    public var order: [DataPart]

    /// Set when nothing was deleted because the deletion couldn't start (Phase 24c).
    public var notStarted: DeletionNotStarted?

    public init(scope: DeletionScope, results: [(DataPart, DeletionOutcome)], notStarted: DeletionNotStarted? = nil) {
        self.scope = scope
        order = results.map(\.0)
        outcomes = Dictionary(results, uniquingKeysWith: { _, last in last })
        self.notStarted = notStarted
    }

    /// Every part was deleted.
    public var isComplete: Bool { notStarted == nil && order.allSatisfy { outcomes[$0] == .deleted } }

    /// Everything on this iPhone is gone; only parts held elsewhere may still be pending or failed.
    public var isLocalComplete: Bool {
        notStarted == nil && order.filter { !$0.isRemote }.allSatisfy { outcomes[$0] == .deleted }
    }

    /// The parts that weren't deleted, in order. Deleting again tries them again.
    public var failedParts: [DataPart] { order.filter { outcomes[$0] == .failed } }

    public var pendingParts: [DataPart] { order.filter { outcomes[$0] == .pending } }
}

/// Deletes her data. The screens only see this protocol.
public protocol DataDeletionService: Sendable {
    /// The scopes she can choose from, plainest first. Stage A: `thisDevice` only.
    var scopes: [DeletionScope] { get }
    /// The parts a scope covers, in the order they're deleted, so the screen can list them first.
    func parts(in scope: DeletionScope) -> [DataPart]
    /// Deletes every part of the scope. A part that fails doesn't stop the others, so as much as
    /// possible is gone, and the report names what's left. Calling it again is safe.
    func delete(_ scope: DeletionScope) async -> DeletionReport
}

/// Delete my data on this iPhone: erases each store through its protocol.
///
/// Drafts and pictures go first, then looks, suitcases and the closet, and the profile last, so a
/// screen that reads in the middle never finds a draft or picture whose pieces are already gone.
public struct LocalDataDeletion: DataDeletionService {
    private let stores: [(DataPart, any ErasableStore)]

    /// - Parameter stores: each part with the store that holds it, in the order to delete them.
    public init(stores: [(DataPart, any ErasableStore)]) {
        self.stores = stores
    }

    /// The order used by `NookServices`: unsaved work, pictures, looks, suitcases, the closet,
    /// then the profile, the tours she has seen and, last, the onboarding state, so the app only
    /// counts as new once everything else has gone.
    public init(
        closet: any ClosetStore, looks: any LookStore, suitcases: any SuitcaseStore, profile: any ProfileStore,
        drafts: any DraftStore, lookDrafts: any LookDraftStore, feedbackDrafts: any FeedbackDraftStore,
        pictures: any TryOnPictureStore, tours: any TourProgressStore, onboarding: any OnboardingStateStore
    ) {
        self.init(
            stores: Self.stores(
                closet: closet, looks: looks, suitcases: suitcases, profile: profile, drafts: drafts,
                lookDrafts: lookDrafts, feedbackDrafts: feedbackDrafts, pictures: pictures, tours: tours,
                onboarding: onboarding))
    }

    /// The stores of `services` in the order `NookServices` erases them, for a deletion that
    /// erases more stores as well (Phase 21a: the store on the iPhone, when a debug launch keeps
    /// the sample closet in memory).
    public static func stores(of services: NookServices) -> [(DataPart, any ErasableStore)] {
        stores(
            closet: services.closet, looks: services.looks, suitcases: services.suitcases, profile: services.profile,
            drafts: services.drafts, lookDrafts: services.lookDrafts, feedbackDrafts: services.feedbackDrafts,
            pictures: services.pictures, tours: services.tours, onboarding: services.onboarding)
    }

    private static func stores(
        closet: any ClosetStore, looks: any LookStore, suitcases: any SuitcaseStore, profile: any ProfileStore,
        drafts: any DraftStore, lookDrafts: any LookDraftStore, feedbackDrafts: any FeedbackDraftStore,
        pictures: any TryOnPictureStore, tours: any TourProgressStore, onboarding: any OnboardingStateStore
    ) -> [(DataPart, any ErasableStore)] {
        [
            (.drafts, drafts),
            (.drafts, lookDrafts),
            (.drafts, feedbackDrafts),
            (.pictures, pictures),
            (.looks, looks),
            (.suitcases, suitcases),
            (.closet, closet),
            (.profile, profile),
            (.profile, tours),
            (.profile, onboarding),
        ]
    }

    public var scopes: [DeletionScope] { [.thisDevice] }

    public func parts(in scope: DeletionScope) -> [DataPart] {
        var parts: [DataPart] = []
        for (part, _) in stores where !parts.contains(part) {
            parts.append(part)
        }
        return parts
    }

    public func delete(_ scope: DeletionScope) async -> DeletionReport {
        var results: [(DataPart, DeletionOutcome)] = []
        for (part, store) in stores {
            let outcome: DeletionOutcome
            do {
                try await store.eraseAll()
                outcome = .deleted
            } catch {
                outcome = .failed
            }
            // A part held by two stores (drafts, the profile) is deleted only if both were erased.
            if let index = results.firstIndex(where: { $0.0 == part }) {
                if outcome == .failed { results[index].1 = .failed }
            } else {
                results.append((part, outcome))
            }
        }
        return DeletionReport(scope: scope, results: results)
    }
}
