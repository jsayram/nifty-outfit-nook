import Foundation
import Models

/// A closet store whose next read can be held, as a slow read would be: the read takes what the
/// store holds at once, then waits until the test lets it go. Every other call goes straight to
/// the store underneath. Tests use it to finish an older load after a newer one.
actor HeldClosetStore: ClosetStore {
    private let base: any ClosetStore
    private var holdsNextRead = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(_ base: any ClosetStore) {
        self.base = base
    }

    /// Holds the next `garments()` or `garment(_:)` after it has read.
    func holdNextRead() {
        holdsNextRead = true
    }

    /// Waits until a read is being held, for up to two seconds.
    func waitForHeldRead() async {
        for _ in 0..<2_000 where held.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Lets every held read return what it read.
    func release() {
        for continuation in held { continuation.resume() }
        held = []
    }

    private func holdIfAsked() async {
        guard holdsNextRead else { return }
        holdsNextRead = false
        await withCheckedContinuation { held.append($0) }
    }

    func garments() async throws(StoreError) -> [Garment] {
        let garments = try await base.garments()
        await holdIfAsked()
        return garments
    }

    func garment(_ id: Garment.ID) async throws(StoreError) -> Garment {
        let garment = try await base.garment(id)
        await holdIfAsked()
        return garment
    }

    func save(_ garment: Garment) async throws(StoreError) { try await base.save(garment) }

    func update(_ id: Garment.ID, _ change: @Sendable (inout Garment) -> Void) async throws(StoreError) -> Garment {
        try await base.update(id, change)
    }

    func recordWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) {
        try await base.recordWear(of: ids, on: date)
    }

    func removeWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) {
        try await base.removeWear(of: ids, on: date)
    }

    func setLaundry(_ state: LaundryState, for ids: [Garment.ID]) async throws(StoreError) {
        try await base.setLaundry(state, for: ids)
    }

    func delete(_ id: Garment.ID, at date: Date) async throws(StoreError) { try await base.delete(id, at: date) }
    func restore(_ id: Garment.ID) async throws(StoreError) { try await base.restore(id) }

    func purgeExpired(asOf date: Date) async throws(StoreError) -> [Garment.ID] {
        try await base.purgeExpired(asOf: date)
    }

    func deletePermanently(_ id: Garment.ID) async throws(StoreError) { try await base.deletePermanently(id) }

    func eraseAll() async throws(StoreError) { try await base.eraseAll() }
}
