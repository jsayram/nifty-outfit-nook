import Foundation

/// Wear today on a look (LR-10): the day goes on the look and on its pieces still in her closet.
/// Laundry is untouched (LR-10, option A).
///
/// It writes to two stores, so it can't be one store call. The look is written first, then the
/// pieces. If the pieces can't be written, the look is put back as it was before, so the look and
/// its pieces never disagree about the day, and the pieces' error is thrown. If putting the look
/// back fails too, the pieces' error is still the one thrown: the screen shows that it didn't
/// work, and reading again shows what was kept.
public struct LookWear: Hashable, Sendable {
    public let lookID: Look.ID
    /// Her pieces in her closet, which get the wear too. Pieces she no longer has don't.
    public let garmentIDs: [Garment.ID]
    public let date: Date

    public init(lookID: Look.ID, garmentIDs: [Garment.ID], date: Date) {
        self.lookID = lookID
        self.garmentIDs = garmentIDs
        self.date = date
    }

    /// Records the wear on the look, then on its pieces.
    public func record(looks: any LookStore, closet: any ClosetStore) async throws(StoreError) {
        let before = try await looks.look(lookID)
        try await looks.recordWear(of: lookID, on: date)
        do {
            try await closet.recordWear(of: garmentIDs, on: date)
        } catch {
            await putBack(before, in: looks)
            throw error
        }
    }

    /// Undo for Wear today, or taking today's wear off again: off the look, then off its pieces.
    public func remove(looks: any LookStore, closet: any ClosetStore) async throws(StoreError) {
        let before = try await looks.look(lookID)
        try await looks.removeWear(of: lookID, on: date)
        do {
            try await closet.removeWear(of: garmentIDs, on: date)
        } catch {
            await putBack(before, in: looks)
            throw error
        }
    }

    /// Puts back the look's wear days as they were.
    private func putBack(_ look: Look, in looks: any LookStore) async {
        let wornOn = look.wornOn
        _ = try? await looks.update(lookID) { $0.wornOn = wornOn }
    }
}
