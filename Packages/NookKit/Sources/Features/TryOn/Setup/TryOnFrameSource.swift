import AVFoundation
import ImageIO
import Models
import SwiftUI
import Synchronization
import UIKit
import UniformTypeIdentifiers

/// Where the try-on camera screen gets its picture and its hints (Phase 33b): the real camera, or a
/// scripted stand-in for tests and the simulator, which has no camera.
@MainActor
protocol TryOnFrameSource: AnyObject {
    /// Whether it can tell what it sees. False when nothing looks at the frames (no Vision), so the
    /// screen says so and leaves the shutter to her.
    var givesGuidance: Bool { get }
    /// Whether there's a second camera to switch to.
    var canFlip: Bool { get }
    /// What was seen in each frame it looked at, `nil` when a frame couldn't be looked at.
    var observations: AsyncStream<FramingObservation?> { get }
    /// Starts the camera. False when it can't start.
    func start() async -> Bool
    func stop()
    func flip() async
    /// The photo, as the camera made it (the intake cleans it), or `nil` when it didn't come out.
    func takePhoto() async -> Data?
    /// The live picture, 3 wide to 4 tall.
    func preview() -> AnyView
}

/// Makes the camera for the try-on photo. The app's is the real one. Debug builds can pass a
/// scripted one (`-fake-camera`), since the simulator has no camera.
public struct TryOnCameraMaker: Sendable {
    let make: @MainActor @Sendable (_ analyzer: (any FrameAnalyzing)?) -> any TryOnFrameSource

    init(_ make: @escaping @MainActor @Sendable (_ analyzer: (any FrameAnalyzing)?) -> any TryOnFrameSource) {
        self.make = make
    }

    public static let live = TryOnCameraMaker { AVTryOnCamera(analyzer: $0) }
}

extension EnvironmentValues {
    @Entry public var tryOnCameraMaker = TryOnCameraMaker.live
}

// MARK: The real camera

/// The device camera for the try-on photo: a preview, a frame every fifth of a second for Vision to
/// look at (and drop: frames are never stored or sent), and the photo itself.
@MainActor
final class AVTryOnCamera: TryOnFrameSource {
    private let engine: CameraEngine
    private let hasAnalyzer: Bool
    private var position = AVCaptureDevice.Position.front

    init(analyzer: (any FrameAnalyzing)?) {
        engine = CameraEngine(analyzer: analyzer)
        hasAnalyzer = analyzer != nil
    }

    var givesGuidance: Bool { hasAnalyzer }

    var canFlip: Bool {
        [AVCaptureDevice.Position.front, .back].allSatisfy {
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: $0) != nil
        }
    }

    var observations: AsyncStream<FramingObservation?> { engine.observations }

    func start() async -> Bool { await engine.start(position: position) }

    func stop() { engine.stop() }

    func flip() async {
        position = position == .front ? .back : .front
        _ = await engine.start(position: position)
    }

    func takePhoto() async -> Data? {
        guard let data = await engine.takePhoto() else { return nil }
        return await CameraPhotoSize.capped(data)
    }

    func preview() -> AnyView { AnyView(CameraPreview(session: engine.session)) }
}

/// The session, the frames and the photo, all on one queue off the main actor. AVFoundation's
/// objects aren't Sendable, so this class is the one place that touches them, from `queue`.
private nonisolated final class CameraEngine: NSObject, @unchecked Sendable,
    AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate
{
    let session = AVCaptureSession()
    let observations: AsyncStream<FramingObservation?>

    private struct State {
        var isAnalyzing = false
        var lastFrame = 0.0
        var photo: CheckedContinuation<Data?, Never>?
    }

    private let continuation: AsyncStream<FramingObservation?>.Continuation
    private let queue = DispatchQueue(label: "nook.tryon.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let analyzer: (any FrameAnalyzing)?
    private let state = Mutex(State())

    init(analyzer: (any FrameAnalyzing)?) {
        self.analyzer = analyzer
        (observations, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        super.init()
    }

    func start(position: AVCaptureDevice.Position) async -> Bool {
        await withCheckedContinuation { result in
            queue.async { result.resume(returning: self.configureAndRun(position)) }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.continuation.finish()
        }
    }

    func takePhoto() async -> Data? {
        await withCheckedContinuation { result in
            queue.async {
                guard self.session.isRunning else { return result.resume(returning: nil) }
                self.state.withLock { $0.photo = result }
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configureAndRun(_ position: AVCaptureDevice.Position) -> Bool {
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
        else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        // Upright in portrait, so what's looked at is what's shown and what's photographed.
        for output in [photoOutput as AVCaptureOutput, videoOutput] {
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
        return session.isRunning
    }

    // MARK: Frames

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        guard let analyzer, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let shouldLook = state.withLock { state in
            // About five looks a second, one at a time: enough for hints, easy on the battery.
            guard !state.isAnalyzing, time - state.lastFrame >= 0.2 else { return false }
            state.isAnalyzing = true
            state.lastFrame = time
            return true
        }
        guard shouldLook else { return }
        let frame = AnalysisFrame(buffer)
        Task { [self] in
            let seen = await analyzer.observe(frame)
            continuation.yield(seen)
            state.withLock { $0.isAnalyzing = false }
        }
    }

    // MARK: The photo

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let waiting = state.withLock { state in
            let waiting = state.photo
            state.photo = nil
            return waiting
        }
        waiting?.resume(returning: data)
    }
}

/// The camera's picture, shown whole (not cropped), so what she sees is what Vision looks at and
/// what the photo shows.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.setNeedsLayout()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer { unsafeDowncast(layer, to: AVCaptureVideoPreviewLayer.self) }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}

/// The try-on photo from the camera is kept at no more than 2,048 pixels on its long side (PR 101:
/// the backend refuses a try-on photo past that, and what the phone sends is made from it at 1,280
/// anyway). A phone's own photo is 3,000 to 4,000 pixels, which only costs space and time in the
/// check. The copy is upright, so it carries no orientation, and is a JPEG; the intake that follows
/// still strips everything else.
nonisolated enum CameraPhotoSize {
    static let longSide = 2_048

    @concurrent
    static func capped(_ data: Data, maxPixelSize: Int = longSide) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
