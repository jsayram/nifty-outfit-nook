import Foundation
import SwiftData

// Phase 20a persistence spike: linking a record and its image file safely (PRD 11.7, "atomic
// record/file linking").
//
// A file and a database row can't be written in one transaction, so the order makes a crash
// harmless: when adding, the file is written whole (temporary file and rename) before the record
// that points to it is saved; when removing, the record goes first and the file after. A crash
// in between can only leave a file nobody points to, never a record pointing at nothing, and
// `reconcile` at launch deletes those files. A file that disappears some other way (a bad
// restore, a damaged device backup) is kept on its record as `missing` and reported, never
// silently dropped.

@ModelActor
actor SpikePhotoLibrary {
    struct Report: Equatable, Sendable {
        var orphanFilesRemoved: [String] = []
        var missingFiles: [String] = []
        var damagedFiles: [String] = []
    }

    private var images: SpikeImageFiles {
        SpikeImageFiles(
            directory: SpikeStoreLocation.imagesDirectory(forStore: modelContainer.configurations.first?.url ?? .temporaryDirectory))
    }

    /// Gives a garment a new original photo, replacing any old one.
    func addPhoto(_ data: Data, photoID: String, to garmentID: String) throws {
        let fileName = SpikeImageFiles.fileName(forPhoto: photoID)
        try images.write(data, named: fileName)
        try SpikeCheckpoint.hit("photo.fileWritten")
        let garment = try garmentRecord(garmentID)
        let replaced = garment.images.map(\.fileName)
        for old in garment.images { modelContext.delete(old) }
        let asset = ImageAssetRecord(
            assetID: "\(garmentID)-\(photoID)", role: "original", fileName: fileName,
            sha256: SpikeImageFiles.sha256(data), byteCount: data.count, state: "present")
        modelContext.insert(asset)
        asset.garment = garment
        garment.photoRef = "stored:\(photoID)"
        try modelContext.save()
        try SpikeCheckpoint.hit("photo.recordSaved")
        for name in replaced where name != fileName { try images.delete(name) }
    }

    /// Removes a garment's photo: the record first, then the file.
    func removePhoto(from garmentID: String) throws {
        let garment = try garmentRecord(garmentID)
        let files = garment.images.map(\.fileName)
        for asset in garment.images { modelContext.delete(asset) }
        garment.photoRef = nil
        try modelContext.save()
        try SpikeCheckpoint.hit("photo.recordRemoved")
        for name in files { try images.delete(name) }
    }

    /// At launch: deletes files no record points to, and marks records whose file is missing or
    /// doesn't match its hash.
    func reconcile() throws -> Report {
        var report = Report()
        let assets = try modelContext.fetch(FetchDescriptor<ImageAssetRecord>())
        let known = Set(assets.map(\.fileName))
        for name in try images.names().sorted() where !known.contains(name) {
            try images.delete(name)
            report.orphanFilesRemoved.append(name)
        }
        for asset in assets {
            guard let file = try images.describe(asset.fileName) else {
                if asset.state != "missing" { asset.state = "missing" }
                report.missingFiles.append(asset.fileName)
                continue
            }
            if file.sha256 != asset.sha256 {
                asset.state = "damaged"
                report.damagedFiles.append(asset.fileName)
            }
        }
        try modelContext.save()
        return report
    }

    func photoState(of garmentID: String) throws -> (ref: String?, files: [String], states: [String]) {
        let garment = try garmentRecord(garmentID)
        return (garment.photoRef, garment.images.map(\.fileName).sorted(), garment.images.map(\.state))
    }

    private func garmentRecord(_ id: String) throws -> GarmentRecord {
        var descriptor = FetchDescriptor<GarmentRecord>(predicate: #Predicate { $0.garmentID == id })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { throw SpikeStoreFailure.sqlite("no \(id)") }
        return record
    }
}
