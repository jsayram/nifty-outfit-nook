import Foundation
import Models
import SwiftData
import Synchronization

/// The real store on the iPhone and every store on it (Phase 21a).
///
/// The app opens it once at launch, before anything reads her data, through the
/// `MigrationCoordinator`. Every store shares the one container; each is an actor with its own
/// context. Release builds keep all her data here. Debug builds keep it here for the empty
/// closet, while the sample closet stays in memory as in Stage A (`docs/models.md`).
///
/// A restore (Phase 21b) writes the store underneath the store actors, which keep what they've
/// read, so afterwards the app calls `reload()` and builds its screens on fresh actors.
public final class NookStorage: Sendable {
    public let container: ModelContainer
    /// Where the store is, for its safety copies. `nil` for a container opened some other way.
    let location: StoreLocation?
    /// Where backups keep their files. `nil` when this storage has no backups (tests).
    public let backupLocation: BackupLocation?
    /// Her image files and their thumbnails (Phase 22b). `nil` without a backup location.
    public let imageFiles: StoredImageFiles?
    private let calendar: Calendar
    private let current: Mutex<Stores>

    /// The stores on an open container.
    public init(
        container: ModelContainer, location: StoreLocation? = nil, backups: BackupLocation? = nil,
        calendar: Calendar = .current
    ) {
        self.container = container
        self.location = location
        backupLocation = backups
        imageFiles = backups.map {
            StoredImageFiles(container: container, location: $0, thumbnails: ThumbnailCache(directory: $0.thumbnails))
        }
        self.calendar = calendar
        current = Mutex(Stores(container: container, calendar: calendar, backups: backups))
    }

    public var closet: StoredClosetStore { current.withLock { $0.closet } }
    public var looks: StoredLookStore { current.withLock { $0.looks } }
    public var suitcases: StoredSuitcaseStore { current.withLock { $0.suitcases } }
    public var pictures: StoredTryOnPictureStore { current.withLock { $0.pictures } }
    public var profile: StoredProfileStore { current.withLock { $0.profile } }
    public var drafts: StoredDraftStore { current.withLock { $0.drafts } }
    public var lookDrafts: StoredLookDraftStore { current.withLock { $0.lookDrafts } }
    public var feedbackDrafts: StoredFeedbackDraftStore { current.withLock { $0.feedbackDrafts } }
    public var onboarding: StoredOnboardingStore { current.withLock { $0.onboarding } }
    public var tours: StoredTourProgressStore { current.withLock { $0.tours } }
    /// Export a copy, Check a copy and Restore. `nil` without a backup location.
    public var backups: LocalBackupService? { current.withLock { $0.backups } }

    /// Fresh store actors on the same container, after a restore or Undo restore changed the
    /// store underneath the old ones.
    public func reload() {
        let fresh = Stores(container: container, calendar: calendar, backups: backupLocation)
        current.withLock { $0 = fresh }
    }

    /// Opens the store at `location`, migrating it if needed. With `backups`, a restore that was
    /// stopped is finished or tidied up first, and an expired safety copy goes (Phase 21b). `now`
    /// is the clock for that check; tests with dates of their own pass theirs.
    public static func open(
        at location: StoreLocation = .app, backups: BackupLocation? = nil, calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) -> Opening {
        switch MigrationCoordinator<NookMigrationPlan>(location: location).open() {
        case .ready(let container, _):
            if let backups { RestoreCommitter(container: container, location: backups, now: now).resume() }
            return .ready(NookStorage(container: container, location: location, backups: backups, calendar: calendar))
        case .problem(let problem):
            return .problem(problem)
        }
    }

    public enum Opening {
        case ready(NookStorage)
        case problem(StoreProblem)
    }

    /// Her data's stores, for `FixtureServices`.
    public var stores: NookStoreSet {
        current.withLock {
            NookStoreSet(
                closet: $0.closet, looks: $0.looks, suitcases: $0.suitcases, profile: $0.profile, drafts: $0.drafts,
                lookDrafts: $0.lookDrafts, pictures: $0.pictures, feedbackDrafts: $0.feedbackDrafts)
        }
    }

    /// The name on the sign and the Style Me settings, kept in the profile record, for the debug
    /// sample closet (`KeptSettingsProfileStore`).
    public var profileSettings: StoredProfileSettingsKeeper {
        StoredProfileSettingsKeeper(container: container)
    }

    /// Her data's stores, each with the part of Delete my data it belongs to, in the order
    /// `LocalDataDeletion` erases them, then the migration's safety copy and the backups' files.
    /// The tours and the onboarding state aren't here: they're in every launch's services already.
    public var erasableData: [(DataPart, any ErasableStore)] {
        var stores: [(DataPart, any ErasableStore)] = [
            (.drafts, drafts), (.drafts, lookDrafts), (.drafts, feedbackDrafts), (.pictures, pictures),
            (.looks, looks), (.suitcases, suitcases), (.closet, closet), (.profile, profile),
        ]
        if let location {
            stores.append((.closet, StoreSafetyCopies(location: location)))
        }
        if let backupLocation {
            stores.append((.closet, BackupDataEraser(container: container, location: backupLocation)))
        }
        return stores
    }

    /// One set of store actors.
    private struct Stores: Sendable {
        let closet: StoredClosetStore
        let looks: StoredLookStore
        let suitcases: StoredSuitcaseStore
        let pictures: StoredTryOnPictureStore
        let profile: StoredProfileStore
        let drafts: StoredDraftStore
        let lookDrafts: StoredLookDraftStore
        let feedbackDrafts: StoredFeedbackDraftStore
        let onboarding: StoredOnboardingStore
        let tours: StoredTourProgressStore
        let backups: LocalBackupService?

        init(container: ModelContainer, calendar: Calendar, backups: BackupLocation?) {
            closet = StoredClosetStore(container: container, calendar: calendar)
            looks = StoredLookStore(container: container, calendar: calendar)
            suitcases = StoredSuitcaseStore(container: container)
            pictures = StoredTryOnPictureStore(modelContainer: container)
            profile = StoredProfileStore(modelContainer: container)
            drafts = StoredDraftStore(modelContainer: container)
            lookDrafts = StoredLookDraftStore(modelContainer: container)
            feedbackDrafts = StoredFeedbackDraftStore(modelContainer: container)
            onboarding = StoredOnboardingStore(modelContainer: container)
            tours = StoredTourProgressStore(modelContainer: container)
            self.backups = backups.map { LocalBackupService(container: container, location: $0) }
        }
    }
}
