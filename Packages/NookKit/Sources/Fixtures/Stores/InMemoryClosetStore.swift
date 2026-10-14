import Foundation
import Models

/// A `ClosetStore` that keeps garments in memory. Nothing is written to disk.
public actor InMemoryClosetStore: ClosetStore {
    private var garmentsByID: [Garment.ID: Garment]
    private let calendar: Calendar
    private let options: StoreOptions

    public init(garments: [Garment], calendar: Calendar, options: StoreOptions = StoreOptions()) {
        garmentsByID = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.calendar = calendar
        self.options = options
    }

    public func garments() async throws(StoreError) -> [Garment] {
        try await options.begin()
        return garmentsByID.values.sorted { lhs, rhs in
            lhs.addedAt != rhs.addedAt ? lhs.addedAt > rhs.addedAt : lhs.id < rhs.id
        }
    }

    public func garment(_ id: Garment.ID) async throws(StoreError) -> Garment {
        try await options.begin()
        return try existing(id)
    }

    public func save(_ garment: Garment) async throws(StoreError) {
        try await options.begin()
        garmentsByID[garment.id] = try checked(garment)
    }

    @discardableResult
    public func update(
        _ id: Garment.ID,
        _ change: @Sendable (inout Garment) -> Void
    ) async throws(StoreError) -> Garment {
        try await options.begin()
        var garment = try existing(id)
        change(&garment)
        let saved = try checked(garment)
        garmentsByID[id] = saved
        return saved
    }

    public func recordWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) {
        try await options.begin()
        try changeEach(ids) { $0.wornOn = WearRules.recording(date, in: $0.wornOn, calendar: calendar) }
    }

    public func removeWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) {
        try await options.begin()
        try changeEach(ids) { $0.wornOn = WearRules.removing(date, from: $0.wornOn, calendar: calendar) }
    }

    public func setLaundry(_ state: LaundryState, for ids: [Garment.ID]) async throws(StoreError) {
        try await options.begin()
        try changeEach(ids) { $0.laundry = state }
    }

    public func delete(_ id: Garment.ID, at date: Date) async throws(StoreError) {
        try await options.begin()
        try changeEach([id]) { $0.deletedAt = date }
    }

    public func restore(_ id: Garment.ID) async throws(StoreError) {
        try await options.begin()
        try changeEach([id]) { $0.deletedAt = nil }
    }

    public func purgeExpired(asOf date: Date) async throws(StoreError) -> [Garment.ID] {
        try await options.begin()
        let expired = garmentsByID.values.filter { garment in
            garment.purgeDate.map { $0 <= date } ?? false
        }
        .map(\.id)
        .sorted()
        for id in expired { garmentsByID[id] = nil }
        return expired
    }

    // MARK: Helpers

    private func existing(_ id: Garment.ID) throws(StoreError) -> Garment {
        guard let garment = garmentsByID[id] else { throw .notFound }
        return garment
    }

    private func checked(_ garment: Garment) throws(StoreError) -> Garment {
        var garment = garment
        do {
            garment.name = try NameRules.garmentName(garment.name)
        } catch {
            throw .invalidName(error)
        }
        return garment
    }

    /// Applies a change to every ID, or to none of them if any ID is unknown.
    private func changeEach(_ ids: [Garment.ID], _ change: (inout Garment) -> Void) throws(StoreError) {
        guard ids.allSatisfy({ garmentsByID[$0] != nil }) else { throw .notFound }
        for id in ids {
            if var garment = garmentsByID[id] {
                change(&garment)
                garmentsByID[id] = garment
            }
        }
    }
}
