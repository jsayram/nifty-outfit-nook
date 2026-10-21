import Foundation
import Models

/// The real photo step (Phase 22a): the screen shows the system photo picker or the camera, and
/// this keeps what she picked. It cleans the photo with `PhotoCleaner` away from the main actor
/// (no location, no camera details, upright) and saves only that copy in `PhotoFileStore`.
/// Nothing leaves the phone and nothing is logged.
///
/// Paste isn't offered: reading the pasteboard makes iOS ask "Allow Paste?" every time, and it's
/// a question for Jose whether it's worth that (the build plan's 22a log).
public struct LocalPhotoIntake: PhotoIntake {
    public let files: PhotoFileStore
    public let options: PhotoCleaner.Options

    public init(files: PhotoFileStore = .app, options: PhotoCleaner.Options = .standard) {
        self.files = files
        self.options = options
    }

    public var sources: [PhotoSource] { [.camera, .library] }
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
/// Release). The bytes are read as they are; `GarmentImageLoader` shrinks them to the size shown.
public struct StoredPhotoProvider: ImageProvider {
    public let files: PhotoFileStore
    public let fallback: any ImageProvider

    public init(files: PhotoFileStore = .app, fallback: any ImageProvider) {
        self.files = files
        self.fallback = fallback
    }

    public func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
        guard case .stored(let id) = reference else {
            return try await fallback.imageData(for: reference, maxPixelSize: maxPixelSize)
        }
        return await Self.read(id.rawValue, from: files)
    }

    @concurrent
    private static func read(_ id: String, from files: PhotoFileStore) async -> Data? {
        files.data(for: id)
    }
}
