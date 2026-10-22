import Foundation
import Models
import SwiftData

// The real stores that hold one record or a few (Phase 21a): her profile, her drafts, the unsent
// feedback note, and the onboarding and tour flags that Stage A kept in `UserDefaults`. Each is a
// `@ModelActor` with its own context on the one store, like the closet stores.

/// Her profile, in the store on the iPhone: the name on the sign, Preferences, fit and
/// measurements, fitting pieces, the try-on photo and the remembered source and occasion.
@ModelActor
public actor StoredProfileStore: ProfileStore {
    private let table = RecordTable<Profile>(kind: .profile)

    public func profile() async throws(StoreError) -> Profile {
        try table.value(RecordKind.singleKey, in: modelContext) ?? Profile()
    }

    /// Checks the sign name, the measurements and each fit piece before saving
    /// (`StoreValidation.profile`).
    public func save(_ profile: Profile) async throws(StoreError) {
        try table.write([RecordKind.singleKey: try StoreValidation.profile(profile)], in: modelContext)
    }

    /// The read, the change and the write happen with nothing in between, on this actor, so two
    /// changes made at once both land.
    @discardableResult
    public func update(_ change: @Sendable (inout Profile) -> Void) async throws(StoreError) -> Profile {
        var profile = try table.value(RecordKind.singleKey, in: modelContext) ?? Profile()
        change(&profile)
        let saved = try StoreValidation.profile(profile)
        try table.write([RecordKind.singleKey: saved], in: modelContext)
        return saved
    }

    /// Delete my data: a fresh profile, as on a new install.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
    }
}

/// Unsaved Add a piece and Edit work, in the store on the iPhone (FR-31). One draft per target.
@ModelActor
public actor StoredDraftStore: DraftStore {
    private let table = RecordTable<GarmentDraft>(kind: .garmentDraft)

    public func drafts() async throws(StoreError) -> [GarmentDraft] {
        try table.all(in: modelContext).values.sorted { $0.savedAt > $1.savedAt }
    }

    public func draft(for target: GarmentDraft.Target) async throws(StoreError) -> GarmentDraft? {
        try table.value(Self.key(target), in: modelContext)
    }

    public func save(_ draft: GarmentDraft) async throws(StoreError) {
        try table.write([Self.key(draft.target): draft], in: modelContext)
    }

    public func discard(_ target: GarmentDraft.Target) async throws(StoreError) {
        try table.write([:], removing: [Self.key(target)], in: modelContext)
    }

    /// Delete my data: every unsaved add and edit.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
    }

    /// The record key for a draft's target: `newPiece`, or `garment:` and the piece's ID.
    static func key(_ target: GarmentDraft.Target) -> String {
        switch target {
        case .newPiece: "newPiece"
        case .garment(let id): "garment:\(id.rawValue)"
        }
    }
}

/// The unsaved Make your own look, in the store on the iPhone (LR-08.4).
@ModelActor
public actor StoredLookDraftStore: LookDraftStore {
    private let table = RecordTable<LookDraft>(kind: .lookDraft)

    public func draft() async throws(StoreError) -> LookDraft? {
        try table.value(RecordKind.singleKey, in: modelContext)
    }

    public func save(_ draft: LookDraft) async throws(StoreError) {
        try table.write([RecordKind.singleKey: draft], in: modelContext)
    }

    public func discard() async throws(StoreError) {
        try table.removeAll(in: modelContext)
    }

    /// Delete my data: the unsaved Make your own look.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
    }
}

/// The unsent Send feedback note, in the store on the iPhone.
@ModelActor
public actor StoredFeedbackDraftStore: FeedbackDraftStore {
    private let table = RecordTable<FeedbackDraft>(kind: .feedbackDraft)

    public func draft() async throws(StoreError) -> FeedbackDraft? {
        try table.value(RecordKind.singleKey, in: modelContext)
    }

    public func save(_ draft: FeedbackDraft) async throws(StoreError) {
        try table.write([RecordKind.singleKey: draft], in: modelContext)
    }

    public func discard() async throws(StoreError) {
        try table.removeAll(in: modelContext)
    }

    /// Delete my data: the unsent note.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
    }
}

/// Whether onboarding was finished, and the closet she started with, in the store on the iPhone.
@ModelActor
public actor StoredOnboardingStore: OnboardingStateStore {
    private let table = RecordTable<StoredOnboarding>(kind: .onboarding)

    public func state() async throws(StoreError) -> OnboardingState {
        guard let stored = try table.value(RecordKind.singleKey, in: modelContext), stored.isCompleted else {
            return .fresh
        }
        return OnboardingState(isCompleted: true, startingCloset: stored.startingCloset ?? .sample)
    }

    public func complete(startingCloset closet: StartingCloset) async throws(StoreError) {
        try table.write(
            [RecordKind.singleKey: StoredOnboarding(isCompleted: true, startingCloset: closet)], in: modelContext)
    }

    /// Delete my data, and the debug `-onboarding reset` flag.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
    }
}

/// Tour progress: the versions seen and the switch in the store on the iPhone, and how each tour
/// ended in memory for the session (Personal in `closet/DATA_MAP.md`, as in Stage A).
@ModelActor
public actor StoredTourProgressStore: TourProgressStore {
    private let table = RecordTable<StoredTours>(kind: .tours)
    /// This session's records.
    private var records: [TourID: TourRecord] = [:]

    public func progress() async throws(StoreError) -> TourProgress {
        let stored = try kept()
        return TourProgress(
            records: records, seenVersions: Self.seen(stored.seenVersions),
            showsTipsOnNewScreens: stored.showsTipsOnNewScreens)
    }

    public func record(_ record: TourRecord) async throws(StoreError) {
        var stored = try kept()
        let key = record.tour.rawValue
        stored.seenVersions[key] = max(stored.seenVersions[key] ?? record.version, record.version)
        try table.write([RecordKind.singleKey: stored], in: modelContext)
        records[record.tour] = record
    }

    public func setShowsTipsOnNewScreens(_ isOn: Bool) async throws(StoreError) {
        var stored = try kept()
        stored.showsTipsOnNewScreens = isOn
        try table.write([RecordKind.singleKey: stored], in: modelContext)
    }

    public func forgetSeenTours() async throws(StoreError) {
        var stored = try kept()
        stored.seenVersions = [:]
        try table.write([RecordKind.singleKey: stored], in: modelContext)
        records = [:]
    }

    /// Delete my data, and the debug `-tour reset` flag: nothing seen and tips back on.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
        records = [:]
    }

    private func kept() throws(StoreError) -> StoredTours {
        try table.value(RecordKind.singleKey, in: modelContext)
            ?? StoredTours(seenVersions: [:], showsTipsOnNewScreens: true)
    }

    /// Only tours the app knows, with a sensible version, so an odd value shows a tour again
    /// rather than never.
    static func seen(_ stored: [String: Int]) -> [TourID: Int] {
        var seen: [TourID: Int] = [:]
        for tour in TourID.all {
            if let version = stored[tour.rawValue], AppStateDefaults.versionRange.contains(version) {
                seen[tour] = version
            }
        }
        return seen
    }
}

/// The name on her sign and the Style Me settings, kept in the profile record in the store
/// (`KeptSettingsProfileStore`). Only the debug sample closet uses it: there the rest of the
/// profile is the sample's, in memory, and comes back as it ships at each launch, as in Stage A.
///
/// The keeper's calls don't wait (`ProfileSettingsKeeper`), so each one makes a short-lived
/// context of its own.
public final class StoredProfileSettingsKeeper: ProfileSettingsKeeper {
    private let container: ModelContainer
    private let table = RecordTable<Profile>(kind: .profile)

    public init(container: ModelContainer) {
        self.container = container
    }

    public func kept() -> KeptProfileSettings {
        guard let profile = try? table.value(RecordKind.singleKey, in: ModelContext(container)) else { return .none }
        return KeptProfileSettings(profile)
    }

    public func keep(_ settings: KeptProfileSettings) {
        let context = ModelContext(container)
        var profile = (try? table.value(RecordKind.singleKey, in: context)) ?? Profile()
        settings.apply(to: &profile)
        try? table.write([RecordKind.singleKey: profile], in: context)
    }

    public func forget() {
        try? table.removeAll(in: ModelContext(container))
    }
}

/// Paid AI jobs (Phase 27c), in the store on the iPhone, so a job carries on after a relaunch
/// with its own Idempotency-Key. Never exported; erased by Delete my data.
@ModelActor
public actor StoredAIJobStore: AIJobStore {
    private let table = RecordTable<AIJob>(kind: .aiJob)

    public func jobs() async throws(StoreError) -> [AIJob] {
        try table.all(in: modelContext).values.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ job: AIJob) async throws(StoreError) {
        try table.write([job.id.rawValue: job], in: modelContext)
    }

    public func remove(_ ids: [AIJob.ID]) async throws(StoreError) {
        try table.write([:], removing: ids.map(\.rawValue), in: modelContext)
    }

    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
    }
}

/// Ask stylist conversations (Phase 27c), in the store on the iPhone. Exported and restored with
/// her looks; erased by Delete my data.
@ModelActor
public actor StoredStylistThreadStore: StylistThreadStore {
    private let table = RecordTable<StylistThread>(kind: .stylistThread)

    public func threads() async throws(StoreError) -> [StylistThread] {
        try table.all(in: modelContext).values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func thread(_ id: StylistThread.ID) async throws(StoreError) -> StylistThread? {
        try table.value(id.rawValue, in: modelContext)
    }

    public func save(_ thread: StylistThread) async throws(StoreError) {
        try table.write([thread.id.rawValue: thread], in: modelContext)
    }

    public func delete(_ id: StylistThread.ID) async throws(StoreError) {
        try table.write([:], removing: [id.rawValue], in: modelContext)
    }

    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
    }
}
