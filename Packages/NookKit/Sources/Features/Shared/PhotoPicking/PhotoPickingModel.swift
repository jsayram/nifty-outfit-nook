import AVFoundation
import Models
import Observation
import UIKit

/// Camera permission and whether there's a camera, behind closures so tests can stand in for
/// iOS (Phase 22a).
struct CameraAccess: Sendable {
    enum Status: Hashable, Sendable {
        case allowed
        /// iOS hasn't asked yet.
        case notAsked
        /// She said no, or turned it off in Settings.
        case denied
        /// Screen Time or a device profile blocks it; she can't change it in the app's settings.
        case restricted
    }

    var status: @Sendable () -> Status
    /// Shows iOS's camera prompt. True when she allows it.
    var request: @Sendable () async -> Bool
    /// False on the simulator, which has no camera.
    var hasCamera: @MainActor () -> Bool

    static let system = CameraAccess(
        status: {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: .allowed
            case .notDetermined: .notAsked
            case .restricted: .restricted
            default: .denied
            }
        },
        request: { await AVCaptureDevice.requestAccess(for: .video) },
        hasCamera: { UIImagePickerController.isSourceTypeAvailable(.camera) }
    )
}

/// What happens after she taps Take photo or Choose from Photos when real photos are on (Phase 22a,
/// `closet/compliance/PERMISSIONS.md`).
///
/// Choose from Photos opens the system picker at once: it runs outside the app and needs no
/// permission. Take photo asks first, in the app's own words, only the first time; Continue
/// shows iOS's prompt and Not now asks nothing. With the camera off, she's told how to turn it
/// on in Settings or to choose a photo instead. Where there's no camera at all (the simulator),
/// she's offered the photo picker.
@Observable
final class PhotoPickingModel {
    enum Step: Hashable {
        /// The app's own words before iOS's camera prompt.
        case cameraExplainer
        /// Camera access is off for the app.
        case cameraOff
        /// The camera can't be used here: none on this device, or blocked by a restriction.
        case cameraUnavailable
        case camera
        case library
    }

    private(set) var step: Step?
    private let access: CameraAccess

    init(access: CameraAccess = .system) {
        self.access = access
    }

    /// Her tap on a photo choice.
    func start(_ source: PhotoSource) {
        switch source {
        case .library, .paste:
            step = .library
        case .camera:
            switch access.status() {
            case .allowed: step = access.hasCamera() ? .camera : .cameraUnavailable
            case .notAsked: step = .cameraExplainer
            case .denied: step = .cameraOff
            case .restricted: step = .cameraUnavailable
            }
        }
    }

    /// Continue on the explainer: iOS asks, then the camera opens if she allowed it.
    func continueToCamera() async {
        step = nil
        let allowed = await access.request()
        if allowed {
            step = access.hasCamera() ? .camera : .cameraUnavailable
        } else {
            step = .cameraOff
        }
    }

    /// "Choose a photo" from the camera messages.
    func chooseFromLibraryInstead() {
        step = .library
    }

    /// Not now, Cancel, or the system screen closed.
    func finish() {
        step = nil
    }

    /// A binding's view of one step, for `.sheet`, `.alert` and the pickers.
    func isShowing(_ shown: Step) -> Bool { step == shown }

    func set(_ shown: Step, isShowing: Bool) {
        if isShowing {
            step = shown
        } else if step == shown {
            step = nil
        }
    }
}
