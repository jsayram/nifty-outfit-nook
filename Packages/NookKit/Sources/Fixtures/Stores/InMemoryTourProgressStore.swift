import Models

/// A `TourProgressStore` that keeps tour progress in memory. Nothing is written to disk, so in
/// Stage A every launch is a first visit, like a fresh install.
public actor InMemoryTourProgressStore: TourProgressStore {
    private var stored: TourProgress
    private let options: StoreOptions

    public init(progress: TourProgress = .fresh, options: StoreOptions = StoreOptions()) {
        stored = progress
        self.options = options
    }

    public func progress() async throws(StoreError) -> TourProgress {
        try await options.begin()
        return stored
    }

    public func record(_ record: TourRecord) async throws(StoreError) {
        try await options.begin()
        stored.add(record)
    }

    public func setShowsTipsOnNewScreens(_ isOn: Bool) async throws(StoreError) {
        try await options.begin()
        stored.showsTipsOnNewScreens = isOn
    }

    public func forgetSeenTours() async throws(StoreError) {
        try await options.begin()
        stored.forgetSeen()
    }

    /// Delete my data: nothing seen and tips back on (PRD §7.8).
    public func eraseAll() async throws(StoreError) {
        try await options.begin()
        stored = .fresh
    }
}
