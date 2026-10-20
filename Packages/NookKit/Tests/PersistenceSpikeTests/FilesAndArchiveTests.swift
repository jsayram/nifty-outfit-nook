import Foundation
import SwiftData
import Testing

/// Records and their image files stay linked through crashes, and an export with the original
/// photos restores into a wiped app, old schema included (Phase 20a, PRD 11.7).
struct FilesAndArchiveTests {
    // MARK: Record and file linking

    @Test(arguments: ["photo.fileWritten", "photo.recordSaved"])
    func addingAPhotoNeverLeavesARecordPointingAtNothing(_ checkpoint: String) async throws {
        let location = try SpikeStoreLocation.temporary("link")
        defer { location.remove() }
        let container = try SpikeSeed.makeCurrentStore(at: location, counts: .small)
        let library = SpikePhotoLibrary(modelContainer: container)
        let photo = SpikeSampleImages.jpeg(seed: 99, byteCount: 4_000)

        await #expect(throws: SimulatedKill.self) {
            try await SpikeCheckpoint.$handler.withValue({ name in
                if name == checkpoint { throw SimulatedKill(checkpoint: name) }
            }) {
                try await library.addPhoto(photo, photoID: "new", to: "g-00001")
            }
        }
        // The next launch.
        let relaunched = SpikePhotoLibrary(modelContainer: try SpikeMigrationCoordinator(location: location).container())
        let report = try await relaunched.reconcile()
        let state = try await relaunched.photoState(of: "g-00001")
        if checkpoint == "photo.fileWritten" {
            // The file was written but the record wasn't: the file is swept, the piece has no photo.
            #expect(report.orphanFilesRemoved == ["new.jpg"])
            #expect(state.ref == nil && state.files.isEmpty)
        } else {
            #expect(report == SpikePhotoLibrary.Report())
            #expect(state.ref == "stored:new" && state.files == ["new.jpg"])
        }
        #expect(report.missingFiles.isEmpty)
    }

    @Test func removingAPhotoAndCrashingLeavesOnlyAFileToSweep() async throws {
        let location = try SpikeStoreLocation.temporary("unlink")
        defer { location.remove() }
        let library = SpikePhotoLibrary(modelContainer: try SpikeSeed.makeCurrentStore(at: location, counts: .small))
        await #expect(throws: SimulatedKill.self) {
            try await SpikeCheckpoint.$handler.withValue({ name in
                if name == "photo.recordRemoved" { throw SimulatedKill(checkpoint: name) }
            }) {
                try await library.removePhoto(from: "g-00000")
            }
        }
        let report = try await library.reconcile()
        #expect(report.orphanFilesRemoved == ["photo-g-00000.jpg"])
        #expect(try await library.photoState(of: "g-00000").ref == nil)
    }

    @Test func aFileLostOutsideTheAppIsReportedAndKeptOnItsRecord() async throws {
        let location = try SpikeStoreLocation.temporary("lost")
        defer { location.remove() }
        let library = SpikePhotoLibrary(modelContainer: try SpikeSeed.makeCurrentStore(at: location, counts: .small))
        let images = SpikeImageFiles(directory: location.imagesDirectory)
        try images.delete("photo-g-00004.jpg")
        try images.write(Data("not the photo".utf8), named: "photo-g-00008.jpg")
        let report = try await library.reconcile()
        #expect(report.missingFiles == ["photo-g-00004.jpg"])
        #expect(report.damagedFiles == ["photo-g-00008.jpg"])
        #expect(try await library.photoState(of: "g-00004").states == ["missing"])
        #expect(try await library.photoState(of: "g-00004").ref == "stored:photo-g-00004")
    }

    // MARK: Export and restore

    @Test func anExportWithOriginalsRestoresIntoAWipedApp() throws {
        let source = try SpikeStoreLocation.temporary("export")
        let archive = try SpikeStoreLocation.temporary("archive")
        let wiped = try SpikeStoreLocation.temporary("wiped")
        defer { [source, archive, wiped].forEach { $0.remove() } }
        _ = try SpikeSeed.makeCurrentStore(at: source, counts: MigrationTests.counts)
        let exported = try SpikeArchive.export(from: source, to: archive.directory)
        #expect(exported.schemaVersion == 3)
        #expect(exported.files.count == exported.store.photoHashes.count)

        _ = try SpikeArchive.restore(from: archive.directory, into: wiped)
        guard case .ready(let container, _) = try SpikeMigrationCoordinator(location: wiped).open() else {
            Issue.record("Expected the restored store to open")
            return
        }
        #expect(try SpikeMigrationCoordinator.verify(container, against: exported.store).isEmpty)
        let original = SpikeImageFiles(directory: source.imagesDirectory)
        let restored = SpikeImageFiles(directory: wiped.imagesDirectory)
        for name in exported.files.keys {
            #expect(try restored.read(name) == original.read(name))
        }
    }

    /// A backup made by an older build restores and migrates like any old store.
    @Test func anOldVersionExportRestoresAndMigrates() throws {
        let source = try SpikeStoreLocation.temporary("old-export")
        let archive = try SpikeStoreLocation.temporary("old-archive")
        let wiped = try SpikeStoreLocation.temporary("old-wiped")
        defer { [source, archive, wiped].forEach { $0.remove() } }
        try SpikeSeed.makeV1Store(at: source, counts: .small, imageBytes: 4_000)
        let exported = try SpikeArchive.export(from: source, to: archive.directory)
        #expect(exported.schemaVersion == 1)
        _ = try SpikeArchive.restore(from: archive.directory, into: wiped)
        guard case .ready(let container, let report) = try SpikeMigrationCoordinator(location: wiped).open() else {
            Issue.record("Expected the restored store to open")
            return
        }
        #expect(report.migratedFrom == .v1)
        #expect(try SpikeMigrationCoordinator.verify(container, against: exported.store).isEmpty)
    }

    /// A damaged photo in the archive stops the restore before anything is copied.
    @Test func aDamagedArchiveIsRefusedBeforeAnythingChanges() throws {
        let source = try SpikeStoreLocation.temporary("bad-export")
        let archive = try SpikeStoreLocation.temporary("bad-archive")
        let wiped = try SpikeStoreLocation.temporary("bad-wiped")
        defer { [source, archive, wiped].forEach { $0.remove() } }
        _ = try SpikeSeed.makeCurrentStore(at: source, counts: .small)
        _ = try SpikeArchive.export(from: source, to: archive.directory)
        let archived = SpikeImageFiles(directory: archive.directory.appending(path: "Images"))
        var bytes = try archived.read("photo-g-00004.jpg")
        bytes[100] ^= 0xFF
        try archived.write(bytes, named: "photo-g-00004.jpg")

        #expect(throws: SpikeArchiveError.damagedFiles(["photo-g-00004.jpg"])) {
            try SpikeArchive.restore(from: archive.directory, into: wiped)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: wiped.directory.path).isEmpty)
    }
}
