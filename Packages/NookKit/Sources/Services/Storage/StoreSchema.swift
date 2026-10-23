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

/// One record of her data. The kind and key together are unique. This is the current version's
/// row (`NookSchemaV2`); `NookSchemaV1.StoredRecord` keeps version 1's as it shipped.
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
    ///
    /// The hash modifier is the store's version 2 (Phase 21c): the columns are the same as
    /// version 1's, but a version 2 store may hold version 2 payloads, which a version 1 build
    /// can't read. The new hash gives the store a new version, so a version 1 build sees a store
    /// from a newer app and leaves it alone instead of opening it. Change it only together with
    /// a new schema version.
    @Attribute(hashModifier: "payload-2")
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

/// The first version of the store (Phases 21a and 21b), frozen: its row exactly as it shipped.
/// Never change it. The app never makes these rows; SwiftData only needs the model to read a
/// version 1 store's metadata and to migrate it.
public enum NookSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [NookSchemaV1.StoredRecord.self] }

    @Model
    public final class StoredRecord {
        #Unique<StoredRecord>([\.kind, \.key])
        #Index<StoredRecord>([\.kind])

        public var kind: String
        public var key: String
        public var payloadVersion: Int
        public var payload: Data
        public var savedAt: Date

        public init(kind: String, key: String, payloadVersion: Int, payload: Data, savedAt: Date) {
            self.kind = kind
            self.key = key
            self.payloadVersion = payloadVersion
            self.payload = payload
            self.savedAt = savedAt
        }
    }
}

/// The second version (Phase 21c): the same columns, marking a store that may hold version 2
/// payloads (`StoredRecord.payloadVersion`). The next version freezes this one's row into the enum
/// before changing `StoredRecord`, as version 1's is.
public enum NookSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    public static var models: [any PersistentModel.Type] { [StoredRecord.self] }
}

/// Every version the app has shipped, oldest first, and the stages between them. The
/// `MigrationCoordinator` reads a store's version from this list before opening it, so a store
/// from a newer app is never opened or reset, and it journals and checks every stage.
public enum NookMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [NookSchemaV1.self, NookSchemaV2.self] }

    /// Version 1 to 2 changes no rows: every payload stays byte for byte, and a version 1 payload
    /// reads as version 2 (`RecordPayload`). The coordinator's check proves it, since it expects
    /// every record's payload hash unchanged.
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: NookSchemaV1.self, toVersion: NookSchemaV2.self)]
    }
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
    /// A paid AI job (Phase 27c), by job ID. This iPhone's work in progress: never exported,
    /// never restored, and a restore leaves it alone.
    case aiJob
    /// An Ask stylist conversation (Phase 27c), by thread ID. Exported and restored like looks.
    case stylistThread
    // iCloud sync's bookkeeping (Phase 21b, decision 0004 §5, THREAT_MODEL D8(d)): in the store,
    // with its file protection, saved after the records it describes. Never exported or synced.
    /// Whether sync is on, for which account, and the engine's saved state. One record.
    case syncState
    /// Per synced record, by record name: its system fields and the version both sides last
    /// agreed on, for three-way merges.
    case syncRecord
    /// A record from another device saved by a newer app version, by record name: kept as it
    /// came and never overwritten, until an update can read it.
    case syncHeld
    /// A value that lost a sync merge, by record name, kept for her to review.
    case syncConflict
    /// Delete my data's request to delete the iCloud copy, content-free (zone names and the
    /// hashed account). Survives Delete my data's erase, so it runs at the next connected launch.
    case syncPendingDeletion

    /// The key of a kind that has one record.
    public static let singleKey = "only"
}
