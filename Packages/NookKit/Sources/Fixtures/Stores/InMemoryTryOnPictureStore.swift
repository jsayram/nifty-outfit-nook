import Foundation
import Models

/// A `TryOnPictureStore` that keeps pictures in memory. Nothing is written to disk, and a
/// simulated picture has no image file to write.
public actor InMemoryTryOnPictureStore: TryOnPictureStore {
    private var picturesByID: [TryOnPicture.ID: TryOnPicture]
    private let options: StoreOptions

    public init(pictures: [TryOnPicture], options: StoreOptions = StoreOptions()) {
        picturesByID = Dictionary(pictures.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.options = options
    }

    public func pictures() async throws(StoreError) -> [TryOnPicture] {
        try await options.begin()
        return TryOnLinks.newestFirst(Array(picturesByID.values))
    }

    public func picture(_ id: TryOnPicture.ID) async throws(StoreError) -> TryOnPicture {
        try await options.begin()
        guard let picture = picturesByID[id] else { throw .notFound }
        return picture
    }

    public func save(_ picture: TryOnPicture) async throws(StoreError) {
        try await options.begin()
        picturesByID[picture.id] = picture
    }

    public func delete(_ id: TryOnPicture.ID) async throws(StoreError) {
        try await options.begin()
        guard picturesByID.removeValue(forKey: id) != nil else { throw .notFound }
    }
}
