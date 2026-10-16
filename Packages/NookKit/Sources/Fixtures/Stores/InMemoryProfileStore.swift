import Models

/// A `ProfileStore` that keeps the profile in memory. Nothing is written to disk.
public actor InMemoryProfileStore: ProfileStore {
    private var stored: Profile
    private let options: StoreOptions

    public init(profile: Profile, options: StoreOptions = StoreOptions()) {
        stored = profile
        self.options = options
    }

    public func profile() async throws(StoreError) -> Profile {
        try await options.begin()
        return stored
    }

    /// Checks the sign name, the measurements and each fit piece before saving
    /// (`StoreValidation.profile`).
    public func save(_ profile: Profile) async throws(StoreError) {
        try await options.begin()
        stored = try StoreValidation.profile(profile)
    }

    @discardableResult
    public func update(_ change: @Sendable (inout Profile) -> Void) async throws(StoreError) -> Profile {
        try await options.begin()
        var profile = stored
        change(&profile)
        stored = try StoreValidation.profile(profile)
        return stored
    }

    /// Delete my data: a fresh profile, as on a new install.
    public func eraseAll() async throws(StoreError) {
        try await options.begin()
        stored = Profile()
    }
}
