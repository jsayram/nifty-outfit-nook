import Foundation
import SwiftData

// The real store's schema (Phase 21a, docs/decisions/0003-persistence-spike.md).
//
// Everything she makes lives in one SwiftData store on the iPhone, as `StoredRecord` rows: a kind
// ("garment", "look", "profile"...), the record's stable ID within that kind, and the value type
// as JSON (`payload`) with the version of that JSON (`payloadVersion`). The screens and the
// stores' callers only ever see the value types (`Garment`, `Look`...), never these rows.
//
// One table with one payload per record follows the 20b design: the export holds JSON records,
// and each CloudKit record will hold one encrypted payload, so the same JSON serves all three.
// It also keeps the SwiftData schema small. The value types change often, and a change to one
// is a change to its Codable shape (`RecordPayload`), not to the schema. The schema still changes
// sometimes (a new column or entity for sync, indexes), and every such change goes through
// `NookMigrationPlan` and the `MigrationCoordinator`, which journals and snapshots it.
//
// Relationships between records are by stable ID inside the payload, never SwiftData
// relationships: a look can refer to a piece that was deleted for good, and PRD 11.7 wants that
// shown as a gap, not dropped (the spike's finding).

/// One record of her data. The kind and key together are unique.
@Model
public final class StoredRecord {
    #Unique<StoredRecord>([\.kind, \.key])
    #Index<StoredRecord>([\.kind])

    /// What the record is (`RecordKind.rawValue`).
    public var kind: String
    /// The record's stable ID within its kind, such as a garment's ID. Kinds with one record use
    /// `RecordKind.singleKey`.
    public var key: String
    /// The version of `payload`'s JSON shape. `RecordPayload` reads every version it knows.
    public var payloadVersion: Int
    /// The value type as JSON.
    public var payload: Data
    /// When the record was last written. Not used for ordering; for recovery and sync later.
    public var savedAt: Date

    public init(kind: String, key: String, payloadVersion: Int, payload: Data, savedAt: Date) {
        self.kind = kind
        self.key = key
        self.payloadVersion = payloadVersion
        self.payload = payload
        self.savedAt = savedAt
    }
}

/// The first version of the store. A later version adds itself here and in `NookMigrationPlan`,
/// with the stage between them, and freezes this one's models (copy the class into the enum)
/// before changing `StoredRecord`.
public enum NookSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [StoredRecord.self] }
}

/// Every version the app has shipped, oldest first, and the stages between them. The
/// `MigrationCoordinator` reads a store's version from this list before opening it, so a store
/// from a newer app is never opened or reset.
public enum NookMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [NookSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

/// The kinds of record in the store.
public enum RecordKind: String, CaseIterable, Sendable {
    case garment
    case look
    case suitcase
    case picture
    /// Unsaved Add a piece and Edit work, one per target.
    case garmentDraft
    /// The unsaved Make your own look. One record.
    case lookDraft
    /// The unsent Send feedback note. One record.
    case feedbackDraft
    /// Her profile. One record.
    case profile
    /// Onboarding finished and the starting closet. One record.
    case onboarding
    /// The tours seen and the tips switch. One record.
    case tours
    /// That the Stage A `UserDefaults` suite was moved in. One record, no content.
    case defaultsImport
    /// A piece deleted for good (Phase 21b): its ID and when, no content. A restore never brings
    /// it back (PRD 11.7, 15.2).
    case deletion
    /// A record that differed in a copy restored with Add what's missing (Phase 21b): the copy's
    /// version, kept for review while this iPhone's stays in place.
    case restoreConflict

    /// The key of a kind that has one record.
    public static let singleKey = "only"
}
