import Models

/// An `OnboardingStateStore` in memory, for tests and previews. The app keeps the state across
/// launches with `DefaultsOnboardingStore` (Services).
public actor InMemoryOnboardingStore: OnboardingStateStore {
    private var stored: OnboardingState
    private let options: StoreOptions

    public init(state: OnboardingState = .fresh, options: StoreOptions = StoreOptions()) {
        stored = state
        self.options = options
    }

    public func state() async throws(StoreError) -> OnboardingState {
        try await options.begin()
        return stored
    }

    public func complete(startingCloset closet: StartingCloset) async throws(StoreError) {
        try await options.begin()
        stored = OnboardingState(isCompleted: true, startingCloset: closet)
    }

    /// Delete my data: onboarding shows again.
    public func eraseAll() async throws(StoreError) {
        try await options.begin()
        stored = .fresh
    }
}
