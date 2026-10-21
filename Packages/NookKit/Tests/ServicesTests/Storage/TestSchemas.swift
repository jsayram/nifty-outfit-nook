import Foundation
import SwiftData

@testable import Services

// A version 3 of the store, one past the app's own, for the migration tests only. It keeps
// `StoredRecord` as it is and adds an entity, so it's a real schema change that needs a migration,
// while the app's own `StoredRecord` class stays valid in this process. (20a found that changing
// a class that other tests in the same process still use makes SwiftData crash when they save.)
// The app's own version 1 to 2 change (Phase 21c) is tested on a real version 1 store file in
// `SchemaV2MigrationTests`.

/// One row per garment record, added by the custom migration stage.
@Model
final class MigrationProbe {
    var key: String

    init(key: String) {
        self.key = key
    }
}

enum TestSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredRecord.self, MigrationProbe.self] }
}

/// Version 2 to 3 with nothing to do but add the table.
enum LightweightPlanV3: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NookSchemaV1.self, NookSchemaV2.self, TestSchemaV3.self] }
    static var stages: [MigrationStage] {
        NookMigrationPlan.stages + [.lightweight(fromVersion: NookSchemaV2.self, toVersion: TestSchemaV3.self)]
    }
}

/// Version 2 to 3 that adds a probe for every garment record, saving every `batchSize`, with a
/// checkpoint after each save: the slow, interruptible kind of migration.
enum CustomPlanV3: SchemaMigrationPlan {
    static let batchSize = 10

    static var schemas: [any VersionedSchema.Type] { [NookSchemaV1.self, NookSchemaV2.self, TestSchemaV3.self] }
    static var stages: [MigrationStage] {
        NookMigrationPlan.stages + [
            .custom(
                fromVersion: NookSchemaV2.self, toVersion: TestSchemaV3.self, willMigrate: nil,
                didMigrate: { context in
                    let garment = RecordKind.garment.rawValue
                    let records = try context.fetch(
                        FetchDescriptor<StoredRecord>(
                            predicate: #Predicate { $0.kind == garment }, sortBy: [SortDescriptor(\.key)]))
                    var batch = 0
                    for (index, record) in records.enumerated() {
                        context.insert(MigrationProbe(key: record.key))
                        if (index + 1).isMultiple(of: batchSize) || index == records.count - 1 {
                            try context.save()
                            batch += 1
                            try StoreCheckpoint.hit("didMigrate.batch.\(batch)")
                        }
                    }
                })
        ]
    }
}

/// A migration with a bug: it loses a record. Verification has to catch it.
enum LosingPlanV3: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NookSchemaV1.self, NookSchemaV2.self, TestSchemaV3.self] }
    static var stages: [MigrationStage] {
        NookMigrationPlan.stages + [
            .custom(
                fromVersion: NookSchemaV2.self, toVersion: TestSchemaV3.self, willMigrate: nil,
                didMigrate: { context in
                    if let record = try context.fetch(FetchDescriptor<StoredRecord>()).first {
                        context.delete(record)
                        try context.save()
                    }
                })
        ]
    }
}
