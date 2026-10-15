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

    /// Checks the sign name, the measurements and each fit piece before saving.
    public func save(_ profile: Profile) async throws(StoreError) {
        try await options.begin()
        var profile = profile
        do {
            profile.signName = try NameRules.signName(profile.signName)
            profile.fitPieces = try profile.fitPieces.map { piece throws(NameProblem) in
                try MeasurementRules.checkedFitPiece(piece)
            }
        } catch {
            throw .invalidName(error)
        }
        let problems = MeasurementRules.problems(in: profile.measurements)
        guard problems.isEmpty else { throw .invalidMeasurements(problems) }
        stored = profile
    }

    /// Delete my data: a fresh profile, as on a new install.
    public func eraseAll() async throws(StoreError) {
        try await options.begin()
        stored = Profile()
    }
}
