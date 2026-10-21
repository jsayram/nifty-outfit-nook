import Foundation
import Models

/// What a restore writes, worked out before anything is written (0004 section 4). Pure, so the
/// rules are tested on their own.
///
/// - Replace: the app's records become the copy's. Every kind a copy carries is replaced.
/// - Add what's missing: records the app doesn't have are added; a record with the same key and
///   a different value keeps this iPhone's version, and the copy's is kept as a `restoreConflict`.
///   Nothing is removed.
///
/// Either way, a piece deleted for good, in the copy or on this iPhone, never comes back, nor do
/// the try-on pictures that show it, and the deletion markers of both are kept. Onboarding is
/// finished afterwards, on her own closet.
struct RestorePlan: Equatable, Sendable {
    /// The rows of the restored kinds when the restore is done. Replace: all of them. Add what's
    /// missing: only the new and changed ones.
    var rows: [StoreRow]
    /// Replace removes every other row of the restored kinds.
    var replacesEverything: Bool
    var added: Int
    var conflicts: Int
    var deletedForGood: Int

    static func make(copy: [StoreRow], phone: [StoreRow], mode: RestoreMode, now: Date) -> RestorePlan {
        let restored = RecordCodec.restoredKinds
        let deletion = RecordKind.deletion.rawValue
        let garment = RecordKind.garment.rawValue
        let phoneRows = phone.filter { restored.contains($0.kind) }
        var markers = Dictionary(
            copy.filter { $0.kind == deletion }.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for row in phoneRows where row.kind == deletion { markers[row.key] = row }
        let candidates = copy.filter { $0.kind != deletion }
        let deleted = candidates.filter { $0.kind == garment && markers[$0.key] != nil }
        // A piece deleted for good takes the try-on pictures that show it (Jose, 20 October 2026).
        let incoming = candidates.filter {
            !($0.kind == garment && markers[$0.key] != nil) && !showsDeletedPiece($0, deleted: markers)
        }

        switch mode {
        case .replace:
            var rows = incoming.filter { $0.kind != RecordKind.onboarding.rawValue } + markers.values
            rows.append(finishedOnboarding(phone: nil))
            return RestorePlan(
                rows: rows.sorted { $0.id < $1.id }, replacesEverything: true, added: incoming.count, conflicts: 0,
                deletedForGood: deleted.count)

        case .addMissing:
            let onPhone = Dictionary(phoneRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var rows: [StoreRow] = []
            var conflicts = 0
            for row in incoming where row.kind != RecordKind.onboarding.rawValue {
                guard let mine = onPhone[row.id] else {
                    rows.append(row)
                    continue
                }
                let same = RecordCodec.byKind[row.kind]?.same(mine, row) ?? (mine.payload == row.payload)
                guard !same, row.kind != RecordKind.restoreConflict.rawValue else { continue }
                conflicts += 1
                rows.append(conflict(row, at: now))
            }
            let added = rows.count - conflicts
            rows += markers.values.filter { onPhone[$0.id] == nil }
            let onboarding = finishedOnboarding(phone: onPhone[onboardingID])
            if onPhone[onboarding.id]?.payload != onboarding.payload { rows.append(onboarding) }
            return RestorePlan(
                rows: rows.sorted { $0.id < $1.id }, replacesEverything: false, added: added, conflicts: conflicts,
                deletedForGood: deleted.count)
        }
    }

    /// A try-on picture that shows a piece deleted for good.
    private static func showsDeletedPiece(_ row: StoreRow, deleted markers: [String: StoreRow]) -> Bool {
        showsDeletedPiece(row, deleted: Set(markers.keys))
    }

    /// A try-on picture that shows one of the pieces `deleted` for good.
    static func showsDeletedPiece(_ row: StoreRow, deleted: Set<String>) -> Bool {
        guard row.kind == RecordKind.picture.rawValue,
            let picture = try? RecordPayload.decode(TryOnPicture.self, from: row.payload, version: row.payloadVersion)
        else { return false }
        return picture.captured.pieces.contains { $0.garmentID.map { deleted.contains($0.rawValue) } ?? false }
    }

    /// The copy's version of a record, kept for review.
    private static func conflict(_ row: StoreRow, at date: Date) -> StoreRow {
        let value = StoredConflict(
            kind: row.kind, key: row.key, payloadVersion: row.payloadVersion, payload: row.payload, foundAt: date)
        return StoreRow(
            kind: RecordKind.restoreConflict.rawValue, key: row.id, payloadVersion: RecordPayload.currentVersion,
            payload: (try? RecordPayload.encode(value)) ?? Data())
    }

    private static let onboardingID = "\(RecordKind.onboarding.rawValue)/\(RecordKind.singleKey)"

    /// Onboarding finished, on her own closet in the store: the phone's record if it already
    /// says so, otherwise a finished one on her own closet. The restored closet is hers, never
    /// the debug sample closet.
    private static func finishedOnboarding(phone: StoreRow?) -> StoreRow {
        let kind = RecordKind.onboarding.rawValue
        if let phone,
            let state = try? RecordPayload.decode(
                StoredOnboarding.self, from: phone.payload, version: phone.payloadVersion),
            state.isCompleted
        {
            return phone
        }
        let finished = StoredOnboarding(isCompleted: true, startingCloset: .empty)
        return StoreRow(
            kind: kind, key: RecordKind.singleKey, payloadVersion: RecordPayload.currentVersion,
            payload: (try? RecordPayload.encode(finished)) ?? Data())
    }

    /// `kind/key` to the SHA-256 of the payload, for every row the plan writes.
    var expected: [String: String] {
        Dictionary(rows.map { ($0.id, BackupFormat.sha256($0.payload)) }, uniquingKeysWith: { _, last in last })
    }
}
