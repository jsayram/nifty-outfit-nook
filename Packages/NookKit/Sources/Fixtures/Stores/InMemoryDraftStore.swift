import Foundation
import Models

/// A `DraftStore` that keeps drafts in memory. Nothing is written to disk, so drafts last until
/// the app is closed (Stage A has no real storage; see `docs/add-a-piece.md`).
///
/// Tests stand in for "the app was closed" by building a new screen model on the same store, and
/// UI tests seed a draft at launch with `-fixtures demo:draft=add`.
public actor InMemoryDraftStore: DraftStore {
    private var draftsByTarget: [GarmentDraft.Target: GarmentDraft]
    private let options: StoreOptions

    public init(drafts: [GarmentDraft] = [], options: StoreOptions = StoreOptions()) {
        draftsByTarget = Dictionary(drafts.map { ($0.target, $0) }, uniquingKeysWith: { _, last in last })
        self.options = options
    }

    public func drafts() async throws(StoreError) -> [GarmentDraft] {
        try await options.begin()
        return draftsByTarget.values.sorted { $0.savedAt > $1.savedAt }
    }

    public func draft(for target: GarmentDraft.Target) async throws(StoreError) -> GarmentDraft? {
        try await options.begin()
        return draftsByTarget[target]
    }

    public func save(_ draft: GarmentDraft) async throws(StoreError) {
        try await options.begin()
        draftsByTarget[draft.target] = draft
    }

    public func discard(_ target: GarmentDraft.Target) async throws(StoreError) {
        try await options.begin()
        draftsByTarget[target] = nil
    }

    /// Delete my data: every unsaved add and edit.
    public func eraseAll() async throws(StoreError) {
        try await options.begin()
        draftsByTarget = [:]
    }
}
