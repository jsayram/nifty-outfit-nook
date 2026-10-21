import Foundation
import Models

/// The real photo step (Phase 22a): the screen shows the system photo picker or the camera, and
/// this keeps what she picked. It cleans the photo with `PhotoCleaner` away from the main actor
/// (no location, no camera details, upright) and saves only that copy in `PhotoFileStore`.
/// Nothing leaves the phone and nothing is logged.
///
/// Paste (Phase 22c) is the system Paste button's: she taps it, iOS hands the screen the copied
/// image, and the screen passes the bytes to `keep` like any picked photo. The app never reads
/// the pasteboard itself, so iOS shows no "Allow Paste?" question.
public struct LocalPhotoIntake: PhotoIntake {
    public let files: PhotoFileStore
    public let options: PhotoCleaner.Options

    public init(files: PhotoFileStore = .app, options: PhotoCleaner.Options = .standard) {
        self.files = files
        self.options = options
    }

    public var sources: [PhotoSource] { [.camera, .library, .paste] }
    public var usesSystemPicker: Bool { true }

    /// Not used: the screen picks the photo and calls `keep`.
    public func photo(from source: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference {
        throw .unreadable
    }

    public func keep(_ data: Data, from source: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference {
        let result = await Self.cleanAndSave(data, files: files, options: options)
        if Task.isCancelled {
            if case .success(let photo) = result { await discard(photo) }
            throw .cancelled
        }
        return try result.get()
    }

    public func discard(_ photo: PhotoReference) async {
        guard case .stored(let id) = photo else { return }
        files.remove(id.rawValue)
    }

    /// Decoding and encoding a 12 MP photo takes a moment, so it never runs on the main actor.
    @concurrent
    private static func cleanAndSave(
        _ data: Data, files: PhotoFileStore, options: PhotoCleaner.Options
    ) async -> Result<PhotoReference, PhotoIntakeError> {
        let clean: PhotoCleaner.CleanPhoto
        do {
            clean = try PhotoCleaner.clean(data, options: options)
        } catch {
            return .failure(error)
        }
        do {
            return .success(.stored(EntityID(try files.add(clean.data))))
        } catch {
            return .failure(.notSaved)
        }
    }
}

/// Garment pictures that include her own photos: a `.stored` reference is read from the photo
/// files, and anything else goes to `fallback` (the sample wardrobe in Debug, nothing in
/// Release). Sizes a thumbnail can serve come from `thumbnails` (Phase 22b), made from the photo
/// the first time; larger ones read the photo itself. `GarmentImageLoader` shrinks the bytes to
/// the size shown.
public struct StoredPhotoProvider: ImageProvider {
    public let files: PhotoFileStore
    public let thumbnails: ThumbnailCache?
    public let fallback: any ImageProvider

    public init(files: PhotoFileStore = .app, thumbnails: ThumbnailCache? = nil, fallback: any ImageProvider) {
        self.files = files
        self.thumbnails = thumbnails
        self.fallback = fallback
    }

    public func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
        guard case .stored(let id) = reference else {
            return try await fallback.imageData(for: reference, maxPixelSize: maxPixelSize)
        }
        return await Self.read(id.rawValue, maxPixelSize: maxPixelSize, from: files, thumbnails: thumbnails)
    }

    @concurrent
    private static func read(
        _ id: String, maxPixelSize: Int, from files: PhotoFileStore, thumbnails: ThumbnailCache?
    ) async -> Data? {
        if let thumbnails, ThumbnailCache.size(for: maxPixelSize) != nil,
            let thumbnail = thumbnails.data(for: id, maxPixelSize: maxPixelSize, original: { files.data(for: id) })
        {
            return thumbnail
        }
        return files.data(for: id)
    }
}
