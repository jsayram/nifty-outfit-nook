import Foundation
import Models
import Synchronization

/// Image files that only remember what they were asked to let go of (Phase 22b).
final class RecordingImageFiles: ImageFiles {
    private let calls = Mutex<[(photos: [PhotoReference], deletedForGood: Bool)]>([])
    private let sweeps = Mutex(0)

    func release(_ photos: [PhotoReference], deletedForGood: Bool) async {
        calls.withLock { $0.append((photos, deletedForGood)) }
    }

    func removeUnused() async { sweeps.withLock { $0 += 1 } }

    /// Every photo released, in order.
    var released: [PhotoReference] { calls.withLock { $0.flatMap(\.photos) } }
    var releasedForGood: [Bool] { calls.withLock { $0.map(\.deletedForGood) } }
}

/// A Try it on that hands back a picture with a stored image, as Phase 33's real one will.
struct StoredImageTryOn: TryOnService {
    let photo: PhotoReference

    func makePicture(of look: Look, at date: Date) async throws(TryOnError) -> TryOnPicture {
        TryOnPicture(id: "p-stored", of: look, image: .generated(photo), createdAt: date)
    }
}
