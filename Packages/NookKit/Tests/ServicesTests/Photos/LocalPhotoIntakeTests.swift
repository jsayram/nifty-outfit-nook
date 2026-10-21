import Foundation
import ImageIO
import Models
import Testing
import UniformTypeIdentifiers

@testable import Services

/// Keeping a photo she picked or took (Phase 22a): only the cleaned copy is written, in the photo
/// folder, and the screens read it back through `StoredPhotoProvider`.
struct LocalPhotoIntakeTests {
    /// A photo folder of its own for one test.
    final class Folder: Sendable {
        let files: PhotoFileStore

        init() {
            files = PhotoFileStore(
                directory: FileManager.default.temporaryDirectory
                    .appending(path: "NookPhotoTests", directoryHint: .isDirectory)
                    .appending(path: UUID().uuidString, directoryHint: .isDirectory))
        }

        deinit {
            try? FileManager.default.removeItem(at: files.directory)
        }
    }

    @Test func aPickedPhotoIsKeptWithoutItsLocation() async throws {
        let folder = Folder()
        let intake = LocalPhotoIntake(files: folder.files)
        let photo = try #require(PhotoWithMetadata.make(HEICSupport.isReliable ? .heic : .jpeg))

        let reference = try await intake.keep(photo, from: .library)

        guard case .stored(let id) = reference else {
            Issue.record("Expected a stored photo, got \(reference)")
            return
        }
        #expect(folder.files.ids() == [id.rawValue])
        let kept = try #require(folder.files.data(for: id.rawValue))
        #expect(kept != photo)
        let properties = try #require(PhotoWithMetadata.properties(of: kept))
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(PhotoWithMetadata.plantedTextFound(in: kept).isEmpty)
    }

    @Test func aCameraPhotoIsCleanedTheSameWay() async throws {
        let folder = Folder()
        let intake = LocalPhotoIntake(files: folder.files)
        let photo = try #require(PhotoWithMetadata.make(.jpeg))
        let reference = try await intake.keep(photo, from: .camera)
        guard case .stored(let id) = reference else {
            Issue.record("Expected a stored photo")
            return
        }
        let kept = try #require(folder.files.data(for: id.rawValue))
        #expect(PhotoWithMetadata.properties(of: kept)?[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test(arguments: [UTType.jpeg, .png, .tiff])
    func aPastedImageIsCleanedLikeAnyOther(type: UTType) async throws {
        let folder = Folder()
        let intake = LocalPhotoIntake(files: folder.files)
        let photo = try #require(PhotoWithMetadata.make(type))
        let reference = try await intake.keep(photo, from: .paste)
        guard case .stored(let id) = reference else {
            Issue.record("Expected a stored photo")
            return
        }
        let kept = try #require(folder.files.data(for: id.rawValue))
        let properties = try #require(PhotoWithMetadata.properties(of: kept))
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(PhotoWithMetadata.plantedTextFound(in: kept).isEmpty)
        #expect(
            CGImageSourceGetType(try #require(CGImageSourceCreateWithData(kept as CFData, nil))) as String?
                == UTType.jpeg.identifier)
    }

    @Test func somethingUnreadableWritesNothing() async {
        let folder = Folder()
        let intake = LocalPhotoIntake(files: folder.files)
        await #expect(throws: PhotoIntakeError.unreadable) {
            try await intake.keep(Data("not a photo".utf8), from: .library)
        }
        #expect(folder.files.ids().isEmpty)
    }

    @Test func aPhotoThatCantBeWrittenSaysSo() async throws {
        // A file where the folder should be: nothing can be written inside it.
        let folder = Folder()
        try FileManager.default.createDirectory(
            at: folder.files.directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("in the way".utf8).write(to: folder.files.directory)
        let intake = LocalPhotoIntake(files: folder.files)
        let photo = try #require(PhotoWithMetadata.make(.jpeg))
        await #expect(throws: PhotoIntakeError.notSaved) {
            try await intake.keep(photo, from: .library)
        }
    }

    @Test func discardRemovesOnlyThatPhoto() async throws {
        let folder = Folder()
        let intake = LocalPhotoIntake(files: folder.files)
        let photo = try #require(PhotoWithMetadata.make(.jpeg))
        let first = try await intake.keep(photo, from: .library)
        let second = try await intake.keep(photo, from: .camera)
        await intake.discard(first)
        await intake.discard(.sample("x-striped-tee"))
        await intake.discard(.noPhoto)
        guard case .stored(let kept) = second else {
            Issue.record("Expected a stored photo")
            return
        }
        #expect(folder.files.ids() == [kept.rawValue])
    }

    @Test func itOffersTheCameraAndPhotosThroughTheSystemScreens() {
        let intake = LocalPhotoIntake(files: Folder().files)
        #expect(intake.usesSystemPicker)
        #expect(intake.sources == [.camera, .library, .paste])
    }

    @Test func theProviderReadsHerPhotosAndPassesTheRestOn() async throws {
        let folder = Folder()
        let intake = LocalPhotoIntake(files: folder.files)
        let photo = try #require(PhotoWithMetadata.make(.jpeg))
        let reference = try await intake.keep(photo, from: .library)
        let provider = StoredPhotoProvider(files: folder.files, fallback: Fallback())

        let stored = try await provider.imageData(for: reference, maxPixelSize: 300)
        #expect(stored != nil)
        #expect(try await provider.imageData(for: .sample("tee"), maxPixelSize: 300) == Data("fallback".utf8))
        #expect(try await provider.imageData(for: .stored(EntityID("missing")), maxPixelSize: 300) == nil)
    }

    @Test func onlyPlainIDsNameAFile() {
        let files = Folder().files
        #expect(files.url(for: "../Store/Nook.store") == nil)
        #expect(files.url(for: "a/b") == nil)
        #expect(files.url(for: "") == nil)
        #expect(files.url(for: "0f8fad5b-d9cb-469f-a165-70867728950e") != nil)
    }

    /// Her photos go where backups look for them, so exports carry them and Delete my data
    /// (`BackupDataEraser`) removes them.
    @Test func photosLiveInTheFolderBackupsCarry() async throws {
        #expect(PhotoFileStore.app.directory == BackupLocation.app.photos)
        let folder = Folder()
        let intake = LocalPhotoIntake(files: folder.files)
        let reference = try await intake.keep(try #require(PhotoWithMetadata.make(.jpeg)), from: .library)
        guard case .stored(let id) = reference else {
            Issue.record("Expected a stored photo")
            return
        }
        #expect(PhotoFiles(directory: folder.files.directory).exists(id.rawValue))
    }

    private struct Fallback: ImageProvider {
        func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
            Data("fallback".utf8)
        }
    }
}
