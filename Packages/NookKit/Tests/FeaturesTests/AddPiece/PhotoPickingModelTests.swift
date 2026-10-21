import Foundation
import Models
import Synchronization
import Testing

@testable import Features

/// Take photo and Choose from Photos with real photos: the camera's permission flow and the
/// fallbacks (Phase 22a, closet/compliance/PERMISSIONS.md).
@MainActor
struct PhotoPickingModelTests {
    /// iOS as the test sets it up, counting the prompts it shows.
    final class FakeCamera: Sendable {
        let state: Mutex<(status: CameraAccess.Status, allows: Bool, prompts: Int)>
        let hasCamera: Bool

        init(_ status: CameraAccess.Status, allows: Bool = true, hasCamera: Bool = true) {
            state = Mutex((status, allows, 0))
            self.hasCamera = hasCamera
        }

        var prompts: Int { state.withLock { $0.prompts } }

        var access: CameraAccess {
            CameraAccess(
                status: { self.state.withLock { $0.status } },
                request: {
                    self.state.withLock {
                        $0.prompts += 1
                        $0.status = $0.allows ? .allowed : .denied
                        return $0.allows
                    }
                },
                hasCamera: { self.hasCamera })
        }
    }

    @Test func choosingFromPhotosAsksForNothing() {
        let camera = FakeCamera(.notAsked)
        let model = PhotoPickingModel(access: camera.access)
        model.start(.library)
        #expect(model.step == .library)
        #expect(camera.prompts == 0)
    }

    @Test func theFirstPhotoExplainsBeforeIOSAsks() async {
        let camera = FakeCamera(.notAsked)
        let model = PhotoPickingModel(access: camera.access)
        model.start(.camera)
        #expect(model.step == .cameraExplainer)
        #expect(camera.prompts == 0)
        await model.continueToCamera()
        #expect(camera.prompts == 1)
        #expect(model.step == .camera)
    }

    @Test func notNowAsksNothing() {
        let camera = FakeCamera(.notAsked)
        let model = PhotoPickingModel(access: camera.access)
        model.start(.camera)
        model.finish()
        #expect(model.step == nil)
        #expect(camera.prompts == 0)
        // Next time she's asked in the app's words again, since iOS never asked.
        model.start(.camera)
        #expect(model.step == .cameraExplainer)
    }

    @Test func sayingNoToIOSOffersSettingsOrAPhoto() async {
        let camera = FakeCamera(.notAsked, allows: false)
        let model = PhotoPickingModel(access: camera.access)
        model.start(.camera)
        await model.continueToCamera()
        #expect(model.step == .cameraOff)
        model.chooseFromLibraryInstead()
        #expect(model.step == .library)
    }

    @Test func cameraOffBeforeGoesStraightToTheMessage() {
        let camera = FakeCamera(.denied)
        let model = PhotoPickingModel(access: camera.access)
        model.start(.camera)
        #expect(model.step == .cameraOff)
        #expect(camera.prompts == 0)
    }

    @Test func allowedOpensTheCamera() {
        let model = PhotoPickingModel(access: FakeCamera(.allowed).access)
        model.start(.camera)
        #expect(model.step == .camera)
    }

    /// The simulator: allowed, but there's no camera, so she's offered the picker.
    @Test func noCameraOffersThePicker() async {
        let camera = FakeCamera(.notAsked, hasCamera: false)
        let model = PhotoPickingModel(access: camera.access)
        model.start(.camera)
        await model.continueToCamera()
        #expect(model.step == .cameraUnavailable)
        model.chooseFromLibraryInstead()
        #expect(model.step == .library)
    }

    @Test func aRestrictedCameraCantBeAskedFor() {
        let camera = FakeCamera(.restricted)
        let model = PhotoPickingModel(access: camera.access)
        model.start(.camera)
        #expect(model.step == .cameraUnavailable)
        #expect(camera.prompts == 0)
    }

    @Test func closingASystemScreenEndsTheStep() {
        let model = PhotoPickingModel(access: FakeCamera(.allowed).access)
        model.start(.library)
        #expect(model.isShowing(.library))
        model.set(.library, isShowing: false)
        #expect(model.step == nil)
        // A stale close for another step changes nothing.
        model.start(.camera)
        model.set(.library, isShowing: false)
        #expect(model.step == .camera)
    }
}
