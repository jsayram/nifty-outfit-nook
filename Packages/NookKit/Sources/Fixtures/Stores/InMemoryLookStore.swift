import Foundation
import Models

/// A `LookStore` that keeps looks in memory. Nothing is written to disk.
public actor InMemoryLookStore: LookStore {
    private var looksByID: [Look.ID: Look]
    private let calendar: Calendar
    private let options: StoreOptions

    public init(looks: [Look], calendar: Calendar, options: StoreOptions = StoreOptions()) {
        looksByID = Dictionary(looks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.calendar = calendar
        self.options = options
    }

    public func looks() async throws(StoreError) -> [Look] {
        try await options.begin()
        return looksByID.values.sorted { lhs, rhs in
            lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id < rhs.id
        }
    }

    public func look(_ id: Look.ID) async throws(StoreError) -> Look {
        try await options.begin()
        return try existing(id)
    }

    public func save(_ look: Look) async throws(StoreError) {
        try await options.begin()
        looksByID[look.id] = try StoreValidation.look(look)
    }

    @discardableResult
    public func update(_ id: Look.ID, _ change: @Sendable (inout Look) -> Void) async throws(StoreError) -> Look {
        try await options.begin()
        var look = try existing(id)
        change(&look)
        let saved = try StoreValidation.look(look)
        looksByID[id] = saved
        return saved
    }

    public func delete(_ id: Look.ID) async throws(StoreError) {
        try await options.begin()
        guard looksByID.removeValue(forKey: id) != nil else { throw .notFound }
    }

    public func recordWear(of id: Look.ID, on date: Date) async throws(StoreError) {
        try await options.begin()
        var look = try existing(id)
        look.wornOn = WearRules.recording(date, in: look.wornOn, calendar: calendar)
        looksByID[id] = look
    }

    public func removeWear(of id: Look.ID, on date: Date) async throws(StoreError) {
        try await options.begin()
        var look = try existing(id)
        look.wornOn = WearRules.removing(date, from: look.wornOn, calendar: calendar)
        looksByID[id] = look
    }

    private func existing(_ id: Look.ID) throws(StoreError) -> Look {
        guard let look = looksByID[id] else { throw .notFound }
        return look
    }

    /// Delete my data: every look, saved or not.
    public func eraseAll() async throws(StoreError) {
        try await options.begin()
        looksByID = [:]
    }
}
