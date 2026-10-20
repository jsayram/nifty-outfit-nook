import Foundation
import SwiftData

// Phase 20a persistence spike. Not shipped: this folder is part of the PersistenceSpikeTests
// target, and the macOS kill harness (KillHarness/run.sh) compiles the files in Spike/ on their
// own. Findings: docs/decisions/0003-persistence-spike.md.
//
// Three versions of a closet schema, so the spike can migrate real stores:
//
// - V1 is Stage A's garment as columns, plus looks and suitcases.
// - V2 is a lightweight step: a sync revision with a default, a new optional date, and a renamed
//   property (`colorNote` becomes `shadeNote`, kept by `originalName`).
// - V3 is a custom step: a new image entity related to its garment, filled in `didMigrate` by
//   hashing every stored photo on disk. That's the slow, interruptible kind of migration.
//
// Looks and suitcases refer to garments by stable ID, not by relationship. Records from sync can
// arrive in any order (a look before its pieces), and PRD 11.7 wants unresolved references kept
// and shown rather than dropped, which a relationship can't hold. Relationships are only used
// inside one record's own parts (a garment and its image files).

/// The first version: Stage A's garment fields as columns.
enum SpikeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [GarmentRecord.self, LookRecord.self, SuitcaseRecord.self] }

    @Model
    final class GarmentRecord {
        @Attribute(.unique) var garmentID: String
        var name: String
        var category: String
        var colors: [String]
        var colorNote: String?
        var fit: String?
        var dressiness: Int
        var warmth: Int
        var seasons: [String]
        var occasions: [String]
        var brand: String?
        var sizeLabel: String?
        var notes: String
        /// `nil` for no photo, `sample:<name>` or `stored:<id>`. A stored photo's original is the
        /// file `<id>.jpg` in the store's `Images` folder.
        var photoRef: String?
        var cutout: Data?
        var ownership: Data
        var laundry: String
        var availability: Data
        var isArchived: Bool
        var deletedAt: Date?
        var wornOn: [Date]
        var addedAt: Date

        init(garmentID: String, name: String, addedAt: Date) {
            self.garmentID = garmentID
            self.name = name
            category = "top"
            colors = []
            dressiness = 1
            warmth = 1
            seasons = []
            occasions = []
            notes = ""
            ownership = Data(#"{"owned":{}}"#.utf8)
            laundry = "clean"
            availability = Data(#"{"available":{}}"#.utf8)
            isArchived = false
            wornOn = []
            self.addedAt = addedAt
        }
    }
}

/// Lightweight: a revision for sync with a default, an optional modified date, and a rename.
enum SpikeSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [GarmentRecord.self, LookRecord.self, SuitcaseRecord.self] }

    @Model
    final class GarmentRecord {
        @Attribute(.unique) var garmentID: String
        var name: String
        var category: String
        var colors: [String]
        @Attribute(originalName: "colorNote") var shadeNote: String?
        var fit: String?
        var dressiness: Int
        var warmth: Int
        var seasons: [String]
        var occasions: [String]
        var brand: String?
        var sizeLabel: String?
        var notes: String
        var photoRef: String?
        var cutout: Data?
        var ownership: Data
        var laundry: String
        var availability: Data
        var isArchived: Bool
        var deletedAt: Date?
        var wornOn: [Date]
        var addedAt: Date
        var revision: Int = 0
        var modifiedAt: Date?

        init(garmentID: String, name: String, addedAt: Date) {
            self.garmentID = garmentID
            self.name = name
            category = "top"
            colors = []
            dressiness = 1
            warmth = 1
            seasons = []
            occasions = []
            notes = ""
            ownership = Data(#"{"owned":{}}"#.utf8)
            laundry = "clean"
            availability = Data(#"{"available":{}}"#.utf8)
            isArchived = false
            wornOn = []
            self.addedAt = addedAt
        }
    }
}

/// Custom: image files become records related to their garment, each with its hash.
enum SpikeSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [GarmentRecord.self, ImageAssetRecord.self, LookRecord.self, SuitcaseRecord.self, SyncStateRecord.self]
    }

    @Model
    final class GarmentRecord {
        @Attribute(.unique) var garmentID: String
        var name: String
        var category: String
        var colors: [String]
        @Attribute(originalName: "colorNote") var shadeNote: String?
        var fit: String?
        var dressiness: Int
        var warmth: Int
        var seasons: [String]
        var occasions: [String]
        var brand: String?
        var sizeLabel: String?
        var notes: String
        var photoRef: String?
        var cutout: Data?
        var ownership: Data
        var laundry: String
        var availability: Data
        var isArchived: Bool
        var deletedAt: Date?
        var wornOn: [Date]
        var addedAt: Date
        var revision: Int = 0
        var modifiedAt: Date?
        @Relationship(deleteRule: .cascade, inverse: \ImageAssetRecord.garment)
        var images: [ImageAssetRecord] = []

        init(garmentID: String, name: String, addedAt: Date) {
            self.garmentID = garmentID
            self.name = name
            category = "top"
            colors = []
            dressiness = 1
            warmth = 1
            seasons = []
            occasions = []
            notes = ""
            ownership = Data(#"{"owned":{}}"#.utf8)
            laundry = "clean"
            availability = Data(#"{"available":{}}"#.utf8)
            isArchived = false
            wornOn = []
            self.addedAt = addedAt
        }
    }

    /// One image file that belongs to a garment: its original photo for now. The bytes stay in a
    /// file; the record holds the name, size and hash, so export, restore and migrations can
    /// prove each file is the one the record expects.
    @Model
    final class ImageAssetRecord {
        @Attribute(.unique) var assetID: String
        /// `original` for now; later `cutout` and `thumbnail`.
        var role: String
        var fileName: String
        var sha256: String
        var byteCount: Int
        /// `present`, or `missing` when the record expects a file that isn't there (kept and
        /// shown, never silently dropped).
        var state: String
        var garment: GarmentRecord?

        init(assetID: String, role: String, fileName: String, sha256: String, byteCount: Int, state: String) {
            self.assetID = assetID
            self.role = role
            self.fileName = fileName
            self.sha256 = sha256
            self.byteCount = byteCount
            self.state = state
        }
    }
}

/// A look. The same in every version, so the schemas share it.
@Model
final class LookRecord {
    @Attribute(.unique) var lookID: String
    var createdAt: Date
    var isSaved: Bool
    /// The pieces it refers to, by ID, for reference checks without decoding the payload.
    var garmentIDs: [String]
    /// The whole look as JSON. Looks change shape often in the PRD; a payload keeps that out of
    /// the schema until the shape settles.
    var payload: Data

    init(lookID: String, createdAt: Date, isSaved: Bool, garmentIDs: [String], payload: Data) {
        self.lookID = lookID
        self.createdAt = createdAt
        self.isSaved = isSaved
        self.garmentIDs = garmentIDs
        self.payload = payload
    }
}

/// A suitcase. The same in every version.
@Model
final class SuitcaseRecord {
    @Attribute(.unique) var suitcaseID: String
    var name: String
    var garmentIDs: [String]
    var payload: Data

    init(suitcaseID: String, name: String, garmentIDs: [String], payload: Data) {
        self.suitcaseID = suitcaseID
        self.name = name
        self.garmentIDs = garmentIDs
        self.payload = payload
    }
}

/// Where `CKSyncEngine`'s state would live: inside the store, as one row, so the change token is
/// saved in the same transaction as the records it describes and has the store's file
/// protection (THREAT_MODEL.md D8(d)).
@Model
final class SyncStateRecord {
    @Attribute(.unique) var key: String
    var serialization: Data

    init(key: String, serialization: Data) {
        self.key = key
        self.serialization = serialization
    }
}

/// V1 to V2 is lightweight; V2 to V3 hashes every stored photo into an image record.
enum SpikeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SpikeSchemaV1.self, SpikeSchemaV2.self, SpikeSchemaV3.self] }
    static var stages: [MigrationStage] { [v1ToV2, v2ToV3] }

    static var v1ToV2: MigrationStage { .lightweight(fromVersion: SpikeSchemaV1.self, toVersion: SpikeSchemaV2.self) }

    static var v2ToV3: MigrationStage {
        .custom(
            fromVersion: SpikeSchemaV2.self, toVersion: SpikeSchemaV3.self, willMigrate: nil,
            didMigrate: { context in try SpikeImageMigration.attachImages(in: context) })
    }
}

/// A plan that stops at V2, as an older build of the app would have. Opening a V3 store with it
/// is what happens after restoring a newer backup into an older app.
enum SpikeMigrationPlanToV2: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SpikeSchemaV1.self, SpikeSchemaV2.self] }
    static var stages: [MigrationStage] { [SpikeMigrationPlan.v1ToV2] }
}

/// The V2 to V3 step: one image record per stored photo, saved in batches.
enum SpikeImageMigration {
    static let batchSize = 200

    static func attachImages(in context: ModelContext) throws {
        guard let storeURL = context.container.configurations.first?.url else { return }
        let images = SpikeImageFiles(directory: SpikeStoreLocation.imagesDirectory(forStore: storeURL))
        let garments = try context.fetch(
            FetchDescriptor<SpikeSchemaV3.GarmentRecord>(sortBy: [SortDescriptor(\.garmentID)]))
        var batch = 0
        for (index, garment) in garments.enumerated() {
            if let photoID = SpikePhotoRef.storedID(garment.photoRef), garment.images.isEmpty {
                let fileName = SpikeImageFiles.fileName(forPhoto: photoID)
                let asset: SpikeSchemaV3.ImageAssetRecord
                if let file = try images.describe(fileName) {
                    asset = .init(
                        assetID: "\(garment.garmentID)-original", role: "original", fileName: fileName,
                        sha256: file.sha256, byteCount: file.byteCount, state: "present")
                } else {
                    asset = .init(
                        assetID: "\(garment.garmentID)-original", role: "original", fileName: fileName, sha256: "",
                        byteCount: 0, state: "missing")
                }
                context.insert(asset)
                asset.garment = garment
            }
            if (index + 1).isMultiple(of: batchSize) || index == garments.count - 1 {
                try context.save()
                batch += 1
                try SpikeCheckpoint.hit("didMigrate.batch.\(batch)")
            }
        }
    }
}

/// `photoRef` values: `nil`, `sample:<name>` or `stored:<id>`.
enum SpikePhotoRef {
    static func storedID(_ ref: String?) -> String? {
        guard let ref, ref.hasPrefix("stored:") else { return nil }
        return String(ref.dropFirst("stored:".count))
    }
}
