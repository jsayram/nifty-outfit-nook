import Foundation
import Models

/// A `SuitcaseStore` that keeps suitcases in memory. Nothing is written to disk.
public actor InMemorySuitcaseStore: SuitcaseStore {
    private var suitcasesByID: [Suitcase.ID: Suitcase]
    private let options: StoreOptions
    private let makeID: @Sendable () -> Suitcase.ID

    /// - Parameter makeID: makes the ID for a new suitcase. Tests pass a fixed one.
    public init(
        suitcases: [Suitcase],
        options: StoreOptions = StoreOptions(),
        makeID: @escaping @Sendable () -> Suitcase.ID = { Suitcase.ID.random() }
    ) {
        suitcasesByID = Dictionary(suitcases.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.options = options
        self.makeID = makeID
    }

    public func suitcases() async throws(StoreError) -> [Suitcase] {
        try await options.begin()
        return suitcasesByID.values.sorted { $0.id < $1.id }
    }

    public func suitcase(_ id: Suitcase.ID) async throws(StoreError) -> Suitcase {
        try await options.begin()
        return try existing(id)
    }

    public func create(name: String, icon: SuitcaseIcon, at date: Date) async throws(StoreError) -> Suitcase {
        try await options.begin()
        let suitcase = Suitcase(id: makeID(), name: try checkedName(name, renaming: nil), icon: icon, createdAt: date)
        suitcasesByID[suitcase.id] = suitcase
        return suitcase
    }

    @discardableResult
    public func update(
        _ id: Suitcase.ID,
        _ change: @Sendable (inout Suitcase) -> Void
    ) async throws(StoreError) -> Suitcase {
        try await options.begin()
        var suitcase = try existing(id)
        change(&suitcase)
        suitcase.name = try checkedName(suitcase.name, renaming: id)
        suitcasesByID[id] = suitcase
        return suitcase
    }

    public func add(_ garmentIDs: [Garment.ID], to id: Suitcase.ID) async throws(StoreError) {
        try await options.begin()
        var suitcase = try existing(id)
        suitcase.garmentIDs.formUnion(garmentIDs)
        suitcasesByID[id] = suitcase
    }

    public func remove(_ garmentIDs: [Garment.ID], from id: Suitcase.ID) async throws(StoreError) {
        try await options.begin()
        var suitcase = try existing(id)
        suitcase.garmentIDs.subtract(garmentIDs)
        suitcasesByID[id] = suitcase
    }

    public func markUsed(_ id: Suitcase.ID, at date: Date) async throws(StoreError) {
        try await options.begin()
        var suitcase = try existing(id)
        suitcase.lastUsedAt = date
        suitcasesByID[id] = suitcase
    }

    public func delete(_ id: Suitcase.ID) async throws(StoreError) {
        try await options.begin()
        guard suitcasesByID.removeValue(forKey: id) != nil else { throw .notFound }
    }

    public func restore(_ suitcase: Suitcase) async throws(StoreError) {
        try await options.begin()
        var restored = suitcase
        restored.name = try checkedName(suitcase.name, renaming: suitcase.id)
        suitcasesByID[suitcase.id] = restored
    }

    private func existing(_ id: Suitcase.ID) throws(StoreError) -> Suitcase {
        guard let suitcase = suitcasesByID[id] else { throw .notFound }
        return suitcase
    }

    private func checkedName(_ name: String, renaming: Suitcase.ID?) throws(StoreError) -> String {
        do {
            return try NameRules.suitcaseName(name, among: Array(suitcasesByID.values), renaming: renaming)
        } catch {
            throw .invalidName(error)
        }
    }

    /// Delete my data: every suitcase, archived ones included.
    public func eraseAll() async throws(StoreError) {
        try await options.begin()
        suitcasesByID = [:]
    }
}
