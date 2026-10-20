import Foundation
import SwiftData

@testable import Services

// A version 2 of the store, for the migration tests only. It keeps `StoredRecord` as it is and
// adds an entity, so it's a real schema change that needs a migration, while the app's own
// `StoredRecord` class stays valid in this process. (20a found that changing a class that other
// tests in the same process still use makes SwiftData crash when they save.) The manual check in
// the 21a log changed `StoredRecord` itself, in a separate build.

/// One row per garment record, added by the custom migration stage.
@Model
final class MigrationProbe {
    var key: String

    init(key: String) {
        self.key = key
    }
}

enum TestSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredRecord.self, MigrationProbe.self] }
}

/// Version 1 to 2 with nothing to do but add the table.
enum LightweightPlanV2: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NookSchemaV1.self, TestSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: NookSchemaV1.self, toVersion: TestSchemaV2.self)]
    }
}

/// Version 1 to 2 that adds a probe for every garment record, saving every `batchSize`, with a
/// checkpoint after each save: the slow, interruptible kind of migration.
enum CustomPlanV2: SchemaMigrationPlan {
    static let batchSize = 10

    static var schemas: [any VersionedSchema.Type] { [NookSchemaV1.self, TestSchemaV2.self] }
    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: NookSchemaV1.self, toVersion: TestSchemaV2.self, willMigrate: nil,
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
enum LosingPlanV2: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NookSchemaV1.self, TestSchemaV2.self] }
    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: NookSchemaV1.self, toVersion: TestSchemaV2.self, willMigrate: nil,
                didMigrate: { context in
                    if let record = try context.fetch(FetchDescriptor<StoredRecord>()).first {
                        context.delete(record)
                        try context.save()
                    }
                })
        ]
    }
}
