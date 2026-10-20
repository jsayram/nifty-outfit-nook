import Models

/// A `FeedbackDraftStore` that keeps the unsent Send feedback note in memory, for tests,
/// previews and the debug `-onboarding skip` launches the UI tests use. The app keeps it in the
/// real store (Phase 21a).
public actor InMemoryFeedbackDraftStore: FeedbackDraftStore {
    private var current: FeedbackDraft?
    private let options: StoreOptions

    public init(draft: FeedbackDraft? = nil, options: StoreOptions = StoreOptions()) {
        current = draft
        self.options = options
    }

    public func draft() async throws(StoreError) -> FeedbackDraft? {
        try await options.begin()
        return current
    }

    public func save(_ draft: FeedbackDraft) async throws(StoreError) {
        try await options.begin()
        current = draft
    }

    public func discard() async throws(StoreError) {
        try await options.begin()
        current = nil
    }

    /// Delete my data: the unsent note.
    public func eraseAll() async throws(StoreError) {
        try await options.begin()
        current = nil
    }
}
