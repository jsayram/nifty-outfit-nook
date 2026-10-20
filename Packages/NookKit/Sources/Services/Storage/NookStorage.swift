import Foundation
import Models
import SwiftData

/// The real store on the iPhone and every store on it (Phase 21a).
///
/// The app opens it once at launch, before anything reads her data, through the
/// `MigrationCoordinator`. Every store shares the one container; each is an actor with its own
/// context. Release builds keep all her data here. Debug builds keep it here for the empty
/// closet, while the sample closet stays in memory as in Stage A (`docs/models.md`).
public final class NookStorage: Sendable {
    public let container: ModelContainer
    /// Where the store is, for its safety copies. `nil` for a container opened some other way.
    let location: StoreLocation?
    public let closet: StoredClosetStore
    public let looks: StoredLookStore
    public let suitcases: StoredSuitcaseStore
    public let pictures: StoredTryOnPictureStore
    public let profile: StoredProfileStore
    public let drafts: StoredDraftStore
    public let lookDrafts: StoredLookDraftStore
    public let feedbackDrafts: StoredFeedbackDraftStore
    public let onboarding: StoredOnboardingStore
    public let tours: StoredTourProgressStore

    /// The stores on an open container.
    public init(container: ModelContainer, location: StoreLocation? = nil, calendar: Calendar = .current) {
        self.container = container
        self.location = location
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
    }

    /// Opens the store at `location`, migrating it if needed.
    public static func open(at location: StoreLocation = .app, calendar: Calendar = .current) -> Opening {
        switch MigrationCoordinator<NookMigrationPlan>(location: location).open() {
        case .ready(let container, _): .ready(NookStorage(container: container, location: location, calendar: calendar))
        case .problem(let problem): .problem(problem)
        }
    }

    public enum Opening {
        case ready(NookStorage)
        case problem(StoreProblem)
    }

    /// Her data's stores, for `FixtureServices`.
    public var stores: NookStoreSet {
        NookStoreSet(
            closet: closet, looks: looks, suitcases: suitcases, profile: profile, drafts: drafts,
            lookDrafts: lookDrafts, pictures: pictures, feedbackDrafts: feedbackDrafts)
    }

    /// The name on the sign and the Style Me settings, kept in the profile record, for the debug
    /// sample closet (`KeptSettingsProfileStore`).
    public var profileSettings: StoredProfileSettingsKeeper {
        StoredProfileSettingsKeeper(container: container)
    }

    /// Her data's stores, each with the part of Delete my data it belongs to, in the order
    /// `LocalDataDeletion` erases them, then the migration's safety copy. The tours and the
    /// onboarding state aren't here: they're in every launch's services already.
    public var erasableData: [(DataPart, any ErasableStore)] {
        var stores: [(DataPart, any ErasableStore)] = [
            (.drafts, drafts), (.drafts, lookDrafts), (.drafts, feedbackDrafts), (.pictures, pictures),
            (.looks, looks), (.suitcases, suitcases), (.closet, closet), (.profile, profile),
        ]
        if let location {
            stores.append((.closet, StoreSafetyCopies(location: location)))
        }
        return stores
    }
}
