import DesignSystem
import Models
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A photo she picked or took, still to be read. The picker hands over a reference and the
/// camera an image; `load` turns either into bytes, away from the button tap, so the screen can
/// show that it's busy meanwhile.
struct PickedPhoto: Sendable {
    let source: PhotoSource
    let load: @Sendable () async throws -> Data
}

/// The provider the Paste button handed over, carried to the loading task. It is used once, to
/// read the image, and nothing else touches it meanwhile.
struct PastedItem: @unchecked Sendable {
    let provider: NSItemProvider
}

extension PickedPhoto {
    /// The largest pasted file the app will read, in bytes. A phone photo is a few megabytes; a
    /// file far beyond this is not one, and reading it all into memory would only hurt.
    static let maximumPastedBytes = 100_000_000

    /// A picture she pasted with the system Paste button (Phase 22c). The button hands over item
    /// providers only for what she tapped; nothing here reads the pasteboard on its own. `nil`
    /// when the paste held no image. The bytes go through the same intake as any other photo.
    static func pasted(_ providers: [NSItemProvider]) -> PickedPhoto? {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else { return nil }
        let item = PastedItem(provider: provider)
        return PickedPhoto(source: .paste) { try await pastedData(from: item) }
    }

    /// The image's bytes in whatever image format the app it came from copied (JPEG, PNG, HEIC,
    /// TIFF, WebP and so on); `PhotoCleaner` decides if it can read them.
    static func pastedData(from item: PastedItem, maximumBytes: Int = maximumPastedBytes) async throws -> Data {
        let data: Data? = await withCheckedContinuation { continuation in
            _ = item.provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { throw PhotoIntakeError.unreadable }
        guard !data.isEmpty, data.count <= maximumBytes else { throw PhotoIntakeError.unreadable }
        return data
    }
}

extension View {
    /// The system photo picker and the camera, with the camera's permission flow (Phase 22a).
    /// `model.start(_:)` begins; `picked` gets the photo. Nothing here reads or keeps the photo:
    /// the screen passes it to `PhotoIntake.keep`, which strips its metadata.
    func photoPicking(_ model: PhotoPickingModel, picked: @escaping (PickedPhoto) -> Void) -> some View {
        modifier(PhotoPickingModifier(model: model, picked: picked))
    }
}

private struct PhotoPickingModifier: ViewModifier {
    let model: PhotoPickingModel
    let picked: (PickedPhoto) -> Void

    @Environment(\.openURL) private var openURL
    @State private var selection: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            // `.current` keeps the photo as stored (usually HEIC) instead of converting it; the
            // app makes its own clean copy anyway.
            .photosPicker(
                isPresented: binding(.library), selection: $selection, matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: selection) { _, item in
                guard let item else { return }
                selection = nil
                picked(
                    PickedPhoto(source: .library) {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw PhotoIntakeError.unreadable
                        }
                        return data
                    })
            }
            .fullScreenCover(isPresented: binding(.camera)) {
                CameraPicker { image in
                    model.finish()
                    guard let image else { return }
                    picked(
                        PickedPhoto(source: .camera) {
                            guard let data = await CameraPicker.encode(image) else { throw PhotoIntakeError.unreadable }
                            return data
                        })
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: binding(.cameraExplainer)) {
                CameraExplainer(
                    proceed: { Task { await model.continueToCamera() } },
                    notNow: { model.finish() })
            }
            // The whole sentence is the title, as PERMISSIONS.md words it, so nothing is said twice.
            .alert(PhotoPickingText.cameraOff, isPresented: binding(.cameraOff)) {
                Button(PhotoPickingText.openSettings) {
                    model.finish()
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button(PhotoPickingText.chooseAPhoto) { model.chooseFromLibraryInstead() }
                Button(PhotoPickingText.cancel, role: .cancel) { model.finish() }
            }
            .alert(PhotoPickingText.noCameraTitle, isPresented: binding(.cameraUnavailable)) {
                Button(PhotoPickingText.chooseAPhoto) { model.chooseFromLibraryInstead() }
                Button(PhotoPickingText.cancel, role: .cancel) { model.finish() }
            } message: {
                Text(PhotoPickingText.noCameraMessage)
            }
    }

    private func binding(_ step: PhotoPickingModel.Step) -> Binding<Bool> {
        Binding(get: { model.isShowing(step) }, set: { model.set(step, isShowing: $0) })
    }
}

/// "Take a photo of a piece": the app's own words before iOS asks for the camera, with Continue
/// (which shows iOS's prompt) and Not now (which asks nothing), so the one prompt isn't spent
/// before she's ready (PERMISSIONS.md).
private struct CameraExplainer: View {
    let proceed: () -> Void
    let notNow: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NookSpacing.large) {
                Image(systemName: "camera")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.nook.accent)
                    .accessibilityHidden(true)
                Text(PhotoPickingText.explainerTitle)
                    .nookTextStyle(.title)
                    .foregroundStyle(.nook.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(PhotoPickingText.explainerMessage)
                    .nookTextStyle(.body)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: NookSpacing.small) {
                    NookButton(PhotoPickingText.continueTitle, systemImage: "camera", fillsWidth: true) {
                        dismiss()
                        proceed()
                    }
                    .accessibilityIdentifier("camera.explainer.continue")
                    NookButton(PhotoPickingText.notNow, kind: .soft, fillsWidth: true) {
                        dismiss()
                        notNow()
                    }
                    .accessibilityIdentifier("camera.explainer.notNow")
                }
            }
            .padding(NookSpacing.large)
        }
        .background(Color.nook.background)
        .presentationDetents([.medium, .large])
    }
}

/// The system camera, for one photo. `UIImagePickerController` is still Apple's camera screen
/// for this; only its photo library mode is deprecated in favour of PHPicker.
struct CameraPicker: UIViewControllerRepresentable {
    /// The photo, or `nil` when she cancelled.
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void

        init(done: @escaping (UIImage?) -> Void) {
            self.done = done
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            done(nil)
        }
    }

    /// The camera's image as a high-quality JPEG, off the main actor. The intake cleans it like
    /// any other photo.
    @concurrent
    nonisolated static func encode(_ image: UIImage) async -> Data? {
        image.jpegData(compressionQuality: 0.95)
    }
}

enum PhotoPickingText {
    static let explainerTitle = String(
        localized: "Take a photo of a piece", bundle: .module, comment: "Before the camera permission prompt: title")
    static let explainerMessage = String(
        localized:
            "The app needs your camera to take the picture. The photo is saved in the app on this iPhone, without its location.",
        bundle: .module, comment: "Before the camera permission prompt (PERMISSIONS.md)")
    static let continueTitle = String(
        localized: "Continue", bundle: .module, comment: "Button: goes on to iOS's camera permission prompt")
    static let notNow = String(
        localized: "Not now", bundle: .module, comment: "Button: closes the camera explainer without asking")
    static let cameraOff = String(
        localized:
            "Camera access is off for Nifty Outfit Nook. You can turn it on in Settings, or choose a photo instead.",
        bundle: .module, comment: "Alert when the camera permission is off (PERMISSIONS.md)")
    static let noCameraTitle = String(
        localized: "The camera isn’t available", bundle: .module,
        comment: "Alert title when there's no camera to use (the simulator, or a restriction)")
    static let noCameraMessage = String(
        localized: "The camera can’t be used here. You can choose a photo instead.", bundle: .module,
        comment: "Alert when there's no camera to use")
    static let openSettings = String(
        localized: "Open Settings", bundle: .module, comment: "Button: opens the app's page in Settings")
    static let chooseAPhoto = String(
        localized: "Choose a photo", bundle: .module, comment: "Button: opens the photo picker instead of the camera")
    static let cancel = String(localized: "Cancel", bundle: .module, comment: "Button: closes a message")
}
