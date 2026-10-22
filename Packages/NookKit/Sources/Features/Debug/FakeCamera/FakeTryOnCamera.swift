#if DEBUG
    import Models
    import SwiftUI
    import UIKit

    /// The way into the stand-in camera from the app target (debug builds only).
    public enum DebugTryOnCamera {
        /// `-fake-camera` was passed.
        public static var isOn: Bool { FakeTryOnCamera.access != nil }

        /// A camera that shows `photo` (a drawn stand-in, never a person) and "takes" it.
        @MainActor public static func maker(photo: Data) -> TryOnCameraMaker { FakeTryOnCamera.maker(photo: photo) }
    }

    /// A stand-in camera for debug builds and the simulator, which has no camera (Phase 33b): it shows
    /// a drawn picture of a made-up person, and sends hints in turn (not in the picture, step back,
    /// arms out, then good), so the guidance, the countdown, the photo and the check before saving can
    /// all be tried. With `-fake-camera`, the app's try-on photo sheet opens it. Never a photo of
    /// anyone, and never in Release.
    @MainActor
    final class FakeTryOnCamera: TryOnFrameSource {
        private let photo: Data
        private let picture: UIImage?
        private let script: [FramingObservation]
        private let step: Duration
        private let continuation: AsyncStream<FramingObservation?>.Continuation
        let observations: AsyncStream<FramingObservation?>
        private var task: Task<Void, Never>?

        let givesGuidance = true
        let canFlip = false

        init(photo: Data, script: [FramingObservation] = FakeTryOnCamera.standardScript, step: Duration = .seconds(1)) {
            self.photo = photo
            self.picture = UIImage(data: photo)
            self.script = script
            self.step = step
            (observations, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        }

        /// With `-fake-camera`, the camera permission and the camera count as there, so the app's
        /// own camera screen opens on the simulator.
        static var access: CameraAccess? {
            ProcessInfo.processInfo.arguments.contains("-fake-camera")
                ? CameraAccess(status: { .allowed }, request: { true }, hasCamera: { true }) : nil
        }

        /// A camera for the app: the drawn photo it will "take", and the hints it gives while she
        /// frames herself.
        static func maker(photo: Data) -> TryOnCameraMaker {
            TryOnCameraMaker { _ in FakeTryOnCamera(photo: photo) }
        }

        func start() async -> Bool {
            task = Task { [continuation, script, step] in
                var index = 0
                while !Task.isCancelled {
                    continuation.yield(script[min(index, script.count - 1)])
                    index += 1
                    try? await Task.sleep(for: step / 2)
                }
            }
            return true
        }

        func stop() {
            task?.cancel()
            continuation.finish()
        }

        func flip() async {}

        func takePhoto() async -> Data? { photo }

        func preview() -> AnyView {
            AnyView(
                Group {
                    if let picture {
                        Image(uiImage: picture).resizable().scaledToFill()
                    } else {
                        Color.gray
                    }
                }
            )
        }

        /// Not in the picture, too close, arms against her sides, then good.
        static var standardScript: [FramingObservation] {
            let noOne = FramingObservation(people: 0)
            let tooClose = FramingObservation(
                people: 1, joints: standing(), outline: CGRect(x: 0.2, y: 0, width: 0.6, height: 1.0))
            let armsIn = FramingObservation(
                people: 1, joints: standing(armsOut: false), outline: CGRect(x: 0.3, y: 0.08, width: 0.4, height: 0.86))
            let good = FramingObservation(
                people: 1, joints: standing(), outline: CGRect(x: 0.2, y: 0.08, width: 0.6, height: 0.86))
            return [noOne, noOne, tooClose, tooClose, tooClose, armsIn, armsIn, armsIn, good]
        }

        /// A standing figure's joints, facing the camera.
        static func standing(armsOut: Bool = true) -> [FramingObservation.Joint: FramingObservation.Point] {
            let reach = armsOut ? 0.2 : 0.09
            func point(_ x: Double, _ y: Double) -> FramingObservation.Point { .init(x: x, y: y) }
            return [
                .nose: point(0.5, 0.12), .leftEye: point(0.48, 0.11), .rightEye: point(0.52, 0.11),
                .neck: point(0.5, 0.2), .leftShoulder: point(0.4, 0.22), .rightShoulder: point(0.6, 0.22),
                .leftElbow: point(0.5 - reach - 0.02, 0.38), .rightElbow: point(0.5 + reach + 0.02, 0.38),
                .leftWrist: point(0.5 - reach, 0.58), .rightWrist: point(0.5 + reach, 0.58),
                .leftHip: point(0.44, 0.54), .rightHip: point(0.56, 0.54), .leftKnee: point(0.44, 0.74),
                .rightKnee: point(0.56, 0.74), .leftAnkle: point(0.44, 0.92), .rightAnkle: point(0.56, 0.92),
            ]
        }
    }
#endif
