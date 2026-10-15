import Foundation
import Models

/// A `LookDraftStore` that keeps the Make your own look draft in memory, so it lasts until the
/// app is closed (Stage A has no real storage). UI tests seed one at launch with
/// `-fixtures demo:draft=look`.
public actor InMemoryLookDraftStore: LookDraftStore {
    private var current: LookDraft?
    private let options: StoreOptions

    public init(draft: LookDraft? = nil, options: StoreOptions = StoreOptions()) {
        current = draft
        self.options = options
    }

    public func draft() async throws(StoreError) -> LookDraft? {
        try await options.begin()
        return current
    }

    public func save(_ draft: LookDraft) async throws(StoreError) {
        try await options.begin()
        current = draft
    }

    public func discard() async throws(StoreError) {
        try await options.begin()
        current = nil
    }
}
