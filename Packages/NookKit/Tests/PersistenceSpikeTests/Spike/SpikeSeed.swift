import CoreData
import Foundation
import SwiftData

// Phase 20a persistence spike: versioned fixture stores.

/// Makes a store at an old schema version, as an older build of the app would have left it.
enum SpikeSeed {
    struct Counts: Sendable {
        var garments: Int
        /// Every `photoEvery`-th garment has a stored photo file.
        var photoEvery: Int
        var looks: Int
        var suitcases: Int

        static let small = Counts(garments: 40, photoEvery: 4, looks: 10, suitcases: 3)
        /// The large fixture's size: 2,400 garments, 600 looks and 40 suitcases, with 300 photos
        /// (PRD 15.3's example closet has 300 photographed garments).
        static let large = Counts(garments: 2_400, photoEvery: 8, looks: 600, suitcases: 40)
    }

    static let epoch = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func garmentID(_ index: Int) -> String { String(format: "g-%05d", index) }

    /// A V1 store with `counts` records, its photo files, and nothing else.
    ///
    /// Written through Core Data with the V1 model, not through V1's `@Model` classes: once a
    /// process has opened a newer version, SwiftData maps every `GarmentRecord` to the newest
    /// entity, and saving a V1 object crashes ("not key value coding-compliant for the key
    /// colorNote"). The app never makes old-version objects, so only fixtures need this.
    static func makeV1Store(at location: SpikeStoreLocation, counts: Counts, imageBytes: Int = 120_000) throws {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let images = SpikeImageFiles(directory: location.imagesDirectory)
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: SpikeStoreVersion.v1.schema) else {
            throw SpikeStoreFailure.sqlite("no V1 model")
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: location.storeURL)
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            for index in 0..<counts.garments {
                let id = garmentID(index)
                let garment = NSEntityDescription.insertNewObject(forEntityName: "GarmentRecord", into: context)
                garment.setValue(id, forKey: "garmentID")
                garment.setValue("Piece \(index)", forKey: "name")
                garment.setValue(["top", "bottom", "dress", "layer", "shoes", "bag"][index % 6], forKey: "category")
                garment.setValue([["navy", "cream"], ["black"], ["pink", "white"]][index % 3], forKey: "colors")
                garment.setValue(index.isMultiple(of: 5) ? "mid-wash \(index)" : nil, forKey: "colorNote")
                garment.setValue(1, forKey: "dressiness")
                garment.setValue(1, forKey: "warmth")
                garment.setValue([String](), forKey: "seasons")
                garment.setValue([String](), forKey: "occasions")
                garment.setValue(index.isMultiple(of: 7) ? "Hem taken up \(index)" : "", forKey: "notes")
                garment.setValue(Data(#"{"owned":{}}"#.utf8), forKey: "ownership")
                garment.setValue("clean", forKey: "laundry")
                garment.setValue(Data(#"{"available":{}}"#.utf8), forKey: "availability")
                garment.setValue(false, forKey: "isArchived")
                garment.setValue(
                    index.isMultiple(of: 3) ? [epoch.addingTimeInterval(Double(index) * 86_400)] : [Date](),
                    forKey: "wornOn")
                garment.setValue(epoch.addingTimeInterval(Double(index) * 3600), forKey: "addedAt")
                if index.isMultiple(of: counts.photoEvery) {
                    garment.setValue("stored:photo-\(id)", forKey: "photoRef")
                    try images.write(
                        SpikeSampleImages.jpeg(seed: UInt64(index), byteCount: imageBytes),
                        named: SpikeImageFiles.fileName(forPhoto: "photo-\(id)"))
                }
                if (index + 1).isMultiple(of: 500) { try context.save() }
            }
            for index in 0..<counts.looks {
                let look = NSEntityDescription.insertNewObject(forEntityName: "LookRecord", into: context)
                look.setValue(String(format: "l-%04d", index), forKey: "lookID")
                look.setValue(epoch, forKey: "createdAt")
                look.setValue(index.isMultiple(of: 2), forKey: "isSaved")
                look.setValue(
                    (0..<3).map { garmentID((index * 7 + $0 * 13) % max(counts.garments, 1)) }, forKey: "garmentIDs")
                look.setValue(Data("{}".utf8), forKey: "payload")
            }
            for index in 0..<counts.suitcases {
                let suitcase = NSEntityDescription.insertNewObject(forEntityName: "SuitcaseRecord", into: context)
                suitcase.setValue(String(format: "s-%03d", index), forKey: "suitcaseID")
                suitcase.setValue("Trip \(index)", forKey: "name")
                suitcase.setValue(
                    (0..<10).map { garmentID((index * 31 + $0) % max(counts.garments, 1)) }, forKey: "garmentIDs")
                suitcase.setValue(Data("{}".utf8), forKey: "payload")
            }
            try context.save()
        }
    }

    /// A store at the current version with the same records, made by migrating a V1 store.
    static func makeCurrentStore(at location: SpikeStoreLocation, counts: Counts) throws -> ModelContainer {
        try makeV1Store(at: location, counts: counts)
        return try SpikeMigrationCoordinator(location: location).container()
    }
}
