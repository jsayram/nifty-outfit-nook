import Fixtures
import Foundation
import ImageIO
import Models
import Synchronization
import Testing

@testable import Services

/// Thumbnails on disk (Phase 22b): made once from the photo, read after that, small, without
/// metadata, kept out of backups, held to their byte limit, and never written when space is short.
struct ThumbnailCacheTests {
    /// A folder of its own for one test, with a photo folder and a thumbnail folder.
    final class Folder: Sendable {
        let root: URL
        let photos: PhotoFileStore
        let thumbnailFolder: URL

        init() {
            root = FileManager.default.temporaryDirectory
                .appending(path: "NookThumbnailTests", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            photos = PhotoFileStore(directory: root.appending(path: "Photos", directoryHint: .isDirectory))
            thumbnailFolder = root.appending(path: "Thumbnails", directoryHint: .isDirectory)
        }

        func cache(byteLimit: Int64 = 200_000_000, freeSpace: Int64 = 10_000_000_000) -> ThumbnailCache {
            ThumbnailCache(directory: thumbnailFolder, byteLimit: byteLimit, freeSpace: { freeSpace })
        }

        func thumbnailNames() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: thumbnailFolder.path)) ?? []).sorted()
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A full-size photo, as an iPhone 12 takes, with metadata planted in it.
    static let photo = PhotoWithMetadata.make(.jpeg, width: 4_032, height: 3_024, orientation: .up)!

    @Test func aThumbnailIsMadeOnceThenRead() throws {
        let folder = Folder()
        let cache = folder.cache()
        let id = try folder.photos.add(Self.photo)
        let reads = Mutex(0)
        let original = {
            reads.withLock { $0 += 1 }
            return folder.photos.data(for: id)
        }

        let first = try #require(cache.data(for: id, maxPixelSize: 400, original: original))
        let second = try #require(cache.data(for: id, maxPixelSize: 512, original: original))

        #expect(first == second)
        #expect(reads.withLock { $0 } == 1)
        #expect(cache.made == 1)
        #expect(folder.thumbnailNames() == ["\(id)-512"])
        let size = try #require(PhotoWithMetadata.storedSize(of: first))
        #expect(max(size.width, size.height) == 512)
        #expect(first.count < Self.photo.count / 10)
        // A fresh cache on the same folder, as after a relaunch, reads the file.
        let relaunched = folder.cache()
        #expect(relaunched.data(for: id, maxPixelSize: 300, original: { nil }) == first)
        #expect(relaunched.made == 0)
    }

    @Test func eachSizeHasItsOwnThumbnailAndLargerOnesReadThePhoto() throws {
        let folder = Folder()
        let cache = folder.cache()
        let id = try folder.photos.add(Self.photo)
        let original = { folder.photos.data(for: id) }

        let medium = try #require(cache.data(for: id, maxPixelSize: 900, original: original))
        #expect(PhotoWithMetadata.storedSize(of: medium).map { max($0.width, $0.height) } == 1_024)
        #expect(cache.data(for: id, maxPixelSize: 2_000, original: original) == nil)
        #expect(ThumbnailCache.size(for: 2_000) == nil)
        #expect(folder.thumbnailNames() == ["\(id)-1024"])
    }

    @Test func aThumbnailCarriesNoMetadata() throws {
        let folder = Folder()
        let id = try folder.photos.add(Self.photo)
        let thumbnail = try #require(folder.cache().data(for: id, maxPixelSize: 512) { Self.photo })
        #expect(PhotoWithMetadata.properties(of: thumbnail)?[kCGImagePropertyGPSDictionary] == nil)
        #expect(PhotoWithMetadata.plantedTextFound(in: thumbnail).isEmpty)
    }

    @Test func aCutoutKeepsItsTransparency() throws {
        let folder = Folder()
        let png = SyntheticGarmentPhotos.cutoutPNG(.flatLayTee, width: 1_152, height: 1_536)
        let thumbnail = try #require(folder.cache().data(for: "cutout-1", maxPixelSize: 512) { png })
        let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.png")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo))
    }

    @Test func theFolderIsLeftOutOfBackups() throws {
        let folder = Folder()
        let id = try folder.photos.add(Self.photo)
        _ = folder.cache().data(for: id, maxPixelSize: 512) { Self.photo }
        let values = try folder.thumbnailFolder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func pastItsLimitTheLeastRecentlyUsedGo() throws {
        let folder = Folder()
        let probe = try #require(ThumbnailCache.make(from: Self.photo, size: 512))
        // Room for three thumbnails, not four.
        let cache = folder.cache(byteLimit: Int64(probe.count) * 3 + Int64(probe.count) / 2)
        let ids = (1...4).map { "photo-\($0)" }
        for id in ids.prefix(3) { _ = cache.data(for: id, maxPixelSize: 512) { Self.photo } }
        // The first is used again, so the second is now the oldest.
        _ = cache.data(for: ids[0], maxPixelSize: 512) { nil }
        _ = cache.data(for: ids[3], maxPixelSize: 512) { Self.photo }

        #expect(cache.bytes <= cache.byteLimit)
        let left = Set(folder.thumbnailNames())
        #expect(left.contains("photo-1-512"))
        #expect(left.contains("photo-4-512"))
        #expect(!left.contains("photo-2-512"))
    }

    @Test func shortOfSpaceNothingIsWrittenButTheThumbnailStillComes() throws {
        let folder = Folder()
        let cache = folder.cache(freeSpace: 100_000_000)
        let thumbnail = cache.data(for: "photo-1", maxPixelSize: 512) { Self.photo }
        #expect(thumbnail != nil)
        #expect(folder.thumbnailNames().isEmpty)
    }

    @Test func aFailedWriteIsntAnError() throws {
        let folder = Folder()
        // A file where the folder should be, so nothing can be written there.
        try FileManager.default.createDirectory(at: folder.root, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: folder.thumbnailFolder)
        let thumbnail = folder.cache().data(for: "photo-1", maxPixelSize: 512) { Self.photo }
        #expect(thumbnail != nil)
    }

    @Test func removingAnImageRemovesItsThumbnails() throws {
        let folder = Folder()
        let cache = folder.cache()
        for id in ["a", "b"] {
            _ = cache.data(for: id, maxPixelSize: 512) { Self.photo }
            _ = cache.data(for: id, maxPixelSize: 1_024) { Self.photo }
        }
        try Data("stray".utf8).write(to: folder.thumbnailFolder.appending(path: "stray.tmp"))

        cache.remove(["a"])
        #expect(folder.thumbnailNames() == ["b-1024", "b-512", "stray.tmp"])
        cache.removeAll(except: ["b"])
        #expect(folder.thumbnailNames() == ["b-1024", "b-512"])
        cache.removeAll(except: [])
        #expect(folder.thumbnailNames().isEmpty)
        #expect(cache.bytes == 0)
    }

    @Test func onlyThumbnailNamesAreReadAsImages() {
        #expect(ThumbnailCache.imageID(inFileName: "0b4f7a9e-1111-4c2a-9a51-photo00000001-512") != nil)
        #expect(ThumbnailCache.imageID(inFileName: "abc-1024") == "abc")
        #expect(ThumbnailCache.imageID(inFileName: "abc-300") == nil)
        #expect(ThumbnailCache.imageID(inFileName: "abc") == nil)
        #expect(ThumbnailCache.imageID(inFileName: "../x-512") == nil)
    }

    @Test func theProviderServesSmallSizesFromThumbnails() async throws {
        let folder = Folder()
        let cache = folder.cache()
        let id = try folder.photos.add(Self.photo)
        let provider = StoredPhotoProvider(files: folder.photos, thumbnails: cache, fallback: NoImages())

        let small = try await provider.imageData(for: .stored(EntityID(id)), maxPixelSize: 480)
        let large = try await provider.imageData(for: .stored(EntityID(id)), maxPixelSize: 3_000)

        #expect(small.flatMap(PhotoWithMetadata.storedSize).map { max($0.width, $0.height) } == 512)
        #expect(large == folder.photos.data(for: id))
        #expect(folder.thumbnailNames() == ["\(id)-512"])
    }

    @Test func aPhotoIsntWrittenWhenTheIPhoneWouldBeTooFull() throws {
        let folder = Folder()
        let tight = PhotoFileStore(directory: folder.photos.directory, freeSpace: { PhotoFileStore.reserve })
        #expect(throws: CocoaError.self) { try tight.add(Self.photo) }
        #expect(tight.ids().isEmpty)
        let roomy = PhotoFileStore(directory: folder.photos.directory, freeSpace: { 10_000_000_000 })
        #expect(throws: Never.self) { _ = try roomy.add(Self.photo) }
    }

    @Test func aFullIPhoneMeansTheIntakeSavesNothing() async throws {
        let folder = Folder()
        let tight = PhotoFileStore(directory: folder.photos.directory, freeSpace: { 1_000_000 })
        await #expect(throws: PhotoIntakeError.notSaved) {
            try await LocalPhotoIntake(files: tight).keep(Self.photo, from: .library)
        }
        #expect(tight.ids().isEmpty)
    }

    @Test func aCutoutIsKeptNextToItsPhoto() throws {
        let folder = Folder()
        let photo = try folder.photos.add(Self.photo)
        let png = SyntheticGarmentPhotos.cutoutPNG(.flatLayTee, width: 600, height: 800)
        let cutout = try folder.photos.addCutout(
            CutoutResult(
                imageData: png, pixelWidth: 600, pixelHeight: 800, quality: StandInCutoutService.cleanQuality))

        guard case .stored(let id) = cutout.image else {
            Issue.record("Expected a stored cutout")
            return
        }
        #expect(Set(folder.photos.ids()) == [photo, id.rawValue])
        #expect(folder.photos.data(for: id.rawValue) == png)
        #expect(cutout.aspectRatio == 0.75)
    }
}

/// A provider with no pictures.
private struct NoImages: ImageProvider {
    func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? { nil }
}
