import Foundation
import Models
import SwiftUI

@testable import Features
@testable import Fixtures

/// The sample wardrobe's real photos for still snapshots, so the Screen Atlas shows the pictures
/// a piece has and not its drawing.
///
/// A still image can't wait for a picture to load, so this loader decodes from the bundled files
/// the moment a view asks, at whatever size it asks for (`GarmentImageLoader.synchronousData`).
/// Every screen snapshot puts it in the environment with `.snapshotPhotos()`; no test picks sizes.
/// Tests about the drawn art leave it off.
@MainActor
enum SnapshotPhotos {
    /// One loader for the whole test run. It holds decoded pictures, so each file is read once
    /// per size however many snapshots use it.
    static let loader: GarmentImageLoader = {
        let loader = GarmentImageLoader(provider: SampleWardrobeProvider(), countLimit: 2_000)
        loader.synchronousData = { reference in
            guard let url = SampleWardrobe.Resource(reference)?.url else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        }
        return loader
    }()
}

extension View {
    /// Shows the sample wardrobe's real photos and cutouts, and try-on previews, in a still render.
    @MainActor func snapshotPhotos() -> some View {
        environment(\.garmentImages, SnapshotPhotos.loader)
    }
}
