import Fixtures
import Foundation
import Models
import Services
import Testing

/// Whether Vision's foreground mask runs where the tests run. The service reports `unsupported`
/// on the iOS simulator (see docs/cutout-feasibility.md), so the tests that need a real cutout
/// are skipped there with that reason, and run on a device.
enum VisionSupport {
    static let skipReason: Comment =
        "Vision's foreground instance mask isn't used on the simulator. Run on a device."

    private static let probe = Task<Bool, Never> {
        do {
            _ = try await VisionCutoutService().cutout(from: SyntheticGarmentPhotos.jpeg(.flatLayTee))
            return true
        } catch {
            return (error as? CutoutError) != .unsupported
        }
    }

    static var isAvailable: Bool {
        get async { await probe.value }
    }
}
