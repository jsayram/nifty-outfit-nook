import DesignSystem
import Models
import SwiftUI
import UIKit

/// Your try-on photo (RD-06, PRD §9.2.1 step 1, `settings.html`'s photo sheet).
///
/// The photo is the picture of her that real try-on pictures will start from (Phase 33). The
/// sheet explains what it's for and how it's kept. She can add it, change it and remove it, and
/// removing never touches the try-on pictures she saved.
///
/// With real photos (Phase 22a, `ownPhoto` set) she can take the photo with the app's own camera
/// (Phase 33b: an outline to stand in, live hints, a timer) or choose one from Photos, which needs
/// no permission. The app keeps its own copy without the location. Either way the photo is checked
/// on the phone with the same fail-closed checks try-on runs, and she sees what it found before it
/// becomes her try-on photo, so a try-on never fails later for a reason she could have fixed.
/// Otherwise (Stage A, the debug sample closet and the screen tests) it offers an example in its
/// place: a sample photo of a woman standing, AI-generated and not her. Either is hidden in the app
/// switcher.
struct TryOnPhotoSheet: View {
    let hasPhoto: Bool
    /// Uses the example photo. Returns false when it wasn't saved.
    let useExample: () async -> Bool
    /// Removes the photo. Returns false when it wasn't saved.
    let remove: () async -> Bool
    /// Her own photo and how to set it, when real photos are on. `nil` shows the example instead.
    var ownPhoto: OwnTryOnPhoto?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.closetIsStillImage) private var isStillImage
    @State private var step: Step
    @State private var isSaving = false
    @State private var didFail = false
    @AccessibilityFocusState private var focusedStep: Step?
    @State private var picking: PhotoPickingModel
    /// 33b: the photo she took or picked, checked, and not yet her try-on photo.
    @State private var candidate: TryOnPhotoCandidate?
    @Environment(\.tryOnCameraMaker) private var cameraMaker

    enum Step: Hashable {
        case main
        /// 33b: the phone is checking the photo she took or picked.
        case checking
        /// 33b: what the check found, with Use this photo or another try.
        case review
        /// "Choose example photo": what she'd pick, as an example.
        case example
        /// "Remove photo?"
        case remove
    }

    init(
        hasPhoto: Bool, step: Step = .main, ownPhoto: OwnTryOnPhoto? = nil, candidate: TryOnPhotoCandidate? = nil,
        useExample: @escaping () async -> Bool, remove: @escaping () async -> Bool
    ) {
        self.hasPhoto = hasPhoto
        self.ownPhoto = ownPhoto
        self.useExample = useExample
        self.remove = remove
        _step = State(initialValue: step)
        _candidate = State(initialValue: candidate)
        #if DEBUG
            // `-fake-camera` (debug builds): the simulator has no camera, so the app's own camera
            // screen opens with a stand-in picture.
            _picking = State(initialValue: PhotoPickingModel(access: FakeTryOnCamera.access ?? .system))
        #else
            _picking = State(initialValue: PhotoPickingModel())
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            switch step {
            case .main: main
            case .checking: checking
            case .review: review
            case .example: example
            case .remove: removal
            }
            if didFail {
                FieldProblemNote(message: ProfileText.failed)
            }
        }
        .onChange(of: step) { _, new in
            didFail = false
            focusedStep = new
        }
        .photoPicking(picking, explainer: .tryOn, camera: cameraContent) { picked in
            receive(picked)
        }
        .onDisappear {
            // A photo she hasn't used goes, as it would if she cancelled.
            if let candidate, let ownPhoto { Task { await ownPhoto.discard(candidate) } }
        }
    }

    /// The guided camera, in place of the system's.
    private var cameraContent: ((_ finish: @escaping CameraFinish) -> AnyView)? {
        guard let ownPhoto else { return nil }
        let frames = ownPhoto.frames
        let maker = cameraMaker
        return { finish in
            AnyView(
                TryOnCaptureScreen(
                    makeModel: { TryOnCaptureModel(source: maker.make(frames)) }, photoTaken: { finish($0) },
                    close: { finish(nil) }))
        }
    }

    // MARK: Steps

    private var main: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            lead(
                String(
                    localized:
                        "This is the photo of you that try-on pictures start from. It’s optional: styling never needs it.",
                    bundle: .module, comment: "Try-on photo sheet: what the photo is for"),
                step: .main)
            if hasPhoto, let photo = ownPhoto?.photo {
                OwnPhotoView(photo: photo)
                    .frame(maxWidth: .infinity)
            } else if hasPhoto {
                ExamplePhoto()
                    .frame(maxWidth: .infinity)
            } else {
                Text(
                    "You can leave this empty and add it later.", bundle: .module,
                    comment: "Try-on photo sheet with no photo"
                )
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if ownPhoto != nil {
                Text(TryOnSetupText.whatHelps)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TryOnSetupText.anyHair)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            privacyPoints
            VStack(spacing: NookSpacing.small) {
                if ownPhoto != nil {
                    NookButton(
                        hasPhoto ? TryOnSetupText.takeNewPhoto : TryOnSetupText.takePhoto, systemImage: "camera",
                        isLoading: isSaving, fillsWidth: true
                    ) {
                        picking.start(.camera)
                    }
                    .accessibilityIdentifier("tryOnPhoto.take")
                    NookButton(
                        hasPhoto ? TryOnSetupText.chooseDifferent : TryOnSetupText.chooseFromPhotos,
                        systemImage: "photo", kind: .soft, isLoading: isSaving, fillsWidth: true
                    ) {
                        picking.start(.library)
                    }
                    .accessibilityIdentifier("tryOnPhoto.chooseOwn")
                } else {
                    NookButton(
                        hasPhoto
                            ? String(
                                localized: "Change example photo", bundle: .module, comment: "Try-on photo sheet button"
                            )
                            : String(
                                localized: "Choose example photo", bundle: .module, comment: "Try-on photo sheet button"
                            ),
                        systemImage: "photo", fillsWidth: true
                    ) {
                        step = .example
                    }
                    .accessibilityIdentifier("tryOnPhoto.choose")
                }
                if hasPhoto {
                    NookButton(
                        String(localized: "Remove photo", bundle: .module, comment: "Try-on photo sheet button"),
                        systemImage: "trash", kind: .soft, fillsWidth: true
                    ) {
                        step = .remove
                    }
                    .accessibilityIdentifier("tryOnPhoto.remove")
                }
                NookButton(
                    String(localized: "Done", bundle: .module, comment: "Button: closes a sheet"), kind: .soft,
                    fillsWidth: true
                ) {
                    dismiss()
                }
                .accessibilityIdentifier("tryOnPhoto.done")
            }
            Group {
                if ownPhoto != nil {
                    Text(TryOnSetupText.ownNote)
                } else {
                    Text(
                        "This test build uses an example photo. It doesn’t ask for your camera or your photos, and nothing is uploaded.",
                        bundle: .module, comment: "Try-on photo sheet: Stage A note")
                }
            }
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var example: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            lead(
                String(
                    localized:
                        "In the finished app you’d pick a photo here: a clear, full-length photo, standing naturally in fitted clothes, in good light. For now, try this example.",
                    bundle: .module, comment: "Try-on photo sheet: the example step"),
                step: .example)
            ExamplePhoto()
                .frame(maxWidth: .infinity)
            VStack(spacing: NookSpacing.small) {
                NookButton(
                    String(localized: "Use example photo", bundle: .module, comment: "Try-on photo sheet button"),
                    systemImage: "checkmark", isLoading: isSaving, fillsWidth: true
                ) {
                    run(useExample)
                }
                .accessibilityIdentifier("tryOnPhoto.useExample")
                NookButton(ProfileText.cancel, kind: .soft, fillsWidth: true) {
                    step = .main
                }
            }
        }
    }

    private var removal: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            lead(
                String(
                    localized: "Remove your try-on photo? Try-on pictures you saved will stay.", bundle: .module,
                    comment: "Try-on photo sheet: asks before removing"),
                step: .remove)
            VStack(spacing: NookSpacing.small) {
                NookButton(
                    String(localized: "Remove photo", bundle: .module, comment: "Try-on photo sheet button"),
                    systemImage: "trash", isLoading: isSaving, fillsWidth: true
                ) {
                    run(remove)
                }
                .accessibilityIdentifier("tryOnPhoto.confirmRemove")
                NookButton(
                    String(localized: "Keep photo", bundle: .module, comment: "Try-on photo sheet button"),
                    kind: .soft, fillsWidth: true
                ) {
                    step = .main
                }
            }
        }
    }

    /// 33b: the phone is checking the photo.
    private var checking: some View {
        VStack(spacing: NookSpacing.large) {
            lead(TryOnSetupText.checking, step: .checking)
            NookLoadingIndicator(label: TryOnSetupText.checking)
            Text(TryOnSetupText.checkingNote)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("tryOnPhoto.checking")
    }

    /// 33b: what the check found, before the photo becomes her try-on photo.
    @ViewBuilder
    private var review: some View {
        if let candidate {
            VStack(alignment: .leading, spacing: NookSpacing.large) {
                switch candidate.check {
                case .fine(let tips):
                    lead(TryOnSetupText.fineTitle, step: .review)
                    OwnPhotoView(photo: candidate.photo)
                        .frame(maxWidth: .infinity)
                    Text(TryOnSetupText.fineMessage)
                        .nookTextStyle(.body)
                        .foregroundStyle(.nook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    tipsList(tips)
                    VStack(spacing: NookSpacing.small) {
                        NookButton(
                            TryOnSetupText.useThisPhoto, systemImage: "checkmark", isLoading: isSaving, fillsWidth: true
                        ) {
                            useCandidate()
                        }
                        .accessibilityIdentifier("tryOnPhoto.use")
                        anotherPhotoButtons(for: candidate, kind: .soft)
                    }
                case .problem(let problem):
                    lead(TryOnSetupText.problemTitle(problem), step: .review)
                    OwnPhotoView(photo: candidate.photo)
                        .frame(maxWidth: .infinity)
                    Text(TryOnSetupText.problemMessage(problem))
                        .nookTextStyle(.body)
                        .foregroundStyle(.nook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: NookSpacing.small) {
                        if problem == .checksUnavailable {
                            // The checks didn't run (Vision isn't there). Try-on checks again before
                            // anything is sent, so keeping the photo is safe.
                            NookButton(
                                TryOnSetupText.checkAgain, systemImage: "arrow.clockwise", isLoading: isSaving,
                                fillsWidth: true
                            ) {
                                checkAgain()
                            }
                            .accessibilityIdentifier("tryOnPhoto.checkAgain")
                            NookButton(TryOnSetupText.keepAnyway, kind: .soft, fillsWidth: true) {
                                useCandidate()
                            }
                            .accessibilityIdentifier("tryOnPhoto.keepAnyway")
                        } else {
                            anotherPhotoButtons(for: candidate, kind: .primary)
                        }
                        if problem == .checksUnavailable {
                            anotherPhotoButtons(for: candidate, kind: .soft)
                        }
                    }
                    Text(TryOnSetupText.problemFooter)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Gentle tips from the framing rules, then the standing note about hats, scarves and
    /// turtlenecks. Never about her hair.
    private func tipsList(_ tips: [FramingAdvice]) -> some View {
        let lines = tips.compactMap(TryOnSetupText.tip)
        return VStack(alignment: .leading, spacing: NookSpacing.small) {
            if !lines.isEmpty {
                Text(TryOnSetupText.tipsTitle)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(TryOnSetupText.hatsNote)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tryOnPhoto.tips")
    }

    /// Take another (from the camera) or choose another (from Photos), and Cancel.
    @ViewBuilder
    private func anotherPhotoButtons(for candidate: TryOnPhotoCandidate, kind: NookButtonKind) -> some View {
        if candidate.source == .camera {
            NookButton(TryOnSetupText.takeAnother, systemImage: "camera", kind: kind, fillsWidth: true) {
                letGo(then: .camera)
            }
            .accessibilityIdentifier("tryOnPhoto.another")
        } else {
            NookButton(TryOnSetupText.chooseAnother, systemImage: "photo", kind: kind, fillsWidth: true) {
                letGo(then: .library)
            }
            .accessibilityIdentifier("tryOnPhoto.another")
        }
        NookButton(
            hasPhoto ? TryOnSetupText.keepCurrent : TryOnSetupText.cancel, kind: .soft, fillsWidth: true
        ) {
            letGo(then: nil)
        }
        .accessibilityIdentifier("tryOnPhoto.cancelCandidate")
    }

    // MARK: Parts

    /// How the photo is kept, in four short points.
    private var privacyPoints: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            point(
                "lock",
                String(localized: "Kept on this iPhone", bundle: .module, comment: "Try-on photo sheet point"),
                String(
                    localized: "It stays with your profile and is hidden when you switch apps.", bundle: .module,
                    comment: "Try-on photo sheet point"))
            point(
                "hand.raised",
                String(localized: "Asked first", bundle: .module, comment: "Try-on photo sheet point"),
                String(
                    localized: "Before a picture is made from it, the app asks you and says where it would go.",
                    bundle: .module, comment: "Try-on photo sheet point (PRD §9.2.1)"))
            point(
                "ruler",
                String(localized: "Never measured", bundle: .module, comment: "Try-on photo sheet point"),
                String(
                    localized: "It’s never used to guess your size or measurements.", bundle: .module,
                    comment: "Try-on photo sheet point (PRD §10.1)"))
            point(
                "trash",
                String(localized: "Yours to remove", bundle: .module, comment: "Try-on photo sheet point"),
                String(
                    localized: "Remove it any time. Pictures you saved stay.", bundle: .module,
                    comment: "Try-on photo sheet point"))
        }
    }

    private func point(_ systemImage: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NookSpacing.medium) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.nook.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                Text(title)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
                Text(text)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The first line of a step. VoiceOver moves to it when the step changes.
    @ViewBuilder
    private func lead(_ text: String, step: Step) -> some View {
        let line = Text(text)
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        // ImageRenderer draws a view with accessibilityFocused as empty space (playbook, Phase 7a).
        if isStillImage {
            line
        } else {
            line.accessibilityFocused($focusedStep, equals: step)
        }
    }

    /// A photo from the camera or Photos: kept without its metadata and checked on the phone, then
    /// shown to her. Nothing is her try-on photo until she says so.
    private func receive(_ picked: PickedPhoto) {
        guard let ownPhoto else { return }
        step = .checking
        Task {
            guard let found = await ownPhoto.prepare(picked) else {
                step = .main
                didFail = true
                return
            }
            candidate = found
            step = .review
        }
    }

    private func useCandidate() {
        guard let ownPhoto, let candidate else { return }
        Task {
            isSaving = true
            let saved = await ownPhoto.save(candidate)
            isSaving = false
            self.candidate = nil
            step = .main
            didFail = !saved
        }
    }

    private func checkAgain() {
        guard let ownPhoto, var current = candidate else { return }
        Task {
            isSaving = true
            current.check = await ownPhoto.check(current.photo)
            candidate = current
            isSaving = false
        }
    }

    /// Lets the photo go (its copy is deleted), then opens the camera or Photos again, or goes back.
    private func letGo(then source: PhotoSource?) {
        guard let ownPhoto, let current = candidate else { return }
        candidate = nil
        step = .main
        Task {
            await ownPhoto.discard(current)
            if let source { picking.start(source) }
        }
    }

    private func run(_ change: @escaping () async -> Bool) {
        Task {
            isSaving = true
            let saved = await change()
            isSaving = false
            if saved {
                step = .main
            } else {
                didFail = true
            }
        }
    }
}

/// Stage A's example try-on photo: a photo of a woman standing, from the sample wardrobe (an
/// AI-generated picture, not a real person and not her), or the try-on backdrop with a photo
/// symbol when the provider has none. Under it, "Example photo". It isn't a try-on picture, so it
/// has no Simulated badge, and nothing covers her face. Hidden in the app switcher like a real
/// photo.
struct ExamplePhoto: View {
    /// 9:16, the shape of a full-length phone photo.
    static let size = CGSize(width: 126, height: 224)

    @Environment(\.garmentImages) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: UIImage?

    private var pixelSize: Int { Int((Self.size.height * displayScale).rounded(.up)) }

    private var photo: UIImage? {
        loaded ?? loader?.cachedImage(for: ProfileModel.exampleTryOnPhoto, maxPixelSize: pixelSize)
    }

    var body: some View {
        let shape = NookRadius.shape(NookRadius.tile)
        VStack(spacing: NookSpacing.small) {
            ZStack {
                LinearGradient(colors: [.nook.artStone, .nook.artSand], startPoint: .top, endPoint: .bottom)
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(.nook.textSecondary)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(shape)
            .background {
                shape
                    .fill(Color.nook.tint)
                    .softShadow(.drop, in: shape)
            }
            .hiddenWhenInactive()
            Text("Example photo", bundle: .module, comment: "Under the example try-on photo")
                .nookTextStyle(.caption)
                .foregroundStyle(.nook.textSecondary)
        }
        .task {
            guard let loader, loaded == nil else { return }
            let image = await loader.image(for: ProfileModel.exampleTryOnPhoto, maxPixelSize: pixelSize)
            if !Task.isCancelled { loaded = image }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                "Example try-on photo. It isn’t a photo of you.", bundle: .module,
                comment: "VoiceOver: the example try-on photo")
        )
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("tryOnPhoto.example")
    }
}

/// Her own try-on photo and how to change it, when real photos are on (Phase 22a, 33b).
struct OwnTryOnPhoto {
    /// Her photo, or `nil` before she has one.
    let photo: PhotoReference?
    /// Looks at the camera's frames for the live hints, or `nil` for none.
    let frames: (any FrameAnalyzing)?
    /// Keeps the photo she took or picked (without its metadata) and checks it. `nil` when it
    /// couldn't be read or kept.
    let prepare: (PickedPhoto) async -> TryOnPhotoCandidate?
    /// Checks a kept photo again.
    let check: (PhotoReference) async -> TryOnPhotoCheck
    /// Makes the photo her try-on photo. False when it wasn't saved (and its copy is gone).
    let save: (TryOnPhotoCandidate) async -> Bool
    /// Deletes a photo she didn't use.
    let discard: (TryOnPhotoCandidate) async -> Void
}

/// Her own try-on photo, 9:16 like the example, hidden in the app switcher. Sensitive
/// (DATA_MAP.md): it's only drawn here, from the photo files on the iPhone.
struct OwnPhotoView: View {
    let photo: PhotoReference

    @Environment(\.garmentImages) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: UIImage?

    private var pixelSize: Int { Int((ExamplePhoto.size.height * displayScale).rounded(.up)) }

    var body: some View {
        let shape = NookRadius.shape(NookRadius.tile)
        ZStack {
            LinearGradient(colors: [.nook.artStone, .nook.artSand], startPoint: .top, endPoint: .bottom)
            if let image = loaded ?? loader?.cachedImage(for: photo, maxPixelSize: pixelSize) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.nook.textSecondary)
            }
        }
        .frame(width: ExamplePhoto.size.width, height: ExamplePhoto.size.height)
        .clipShape(shape)
        .background {
            shape
                .fill(Color.nook.tint)
                .softShadow(.drop, in: shape)
        }
        .hiddenWhenInactive()
        .task(id: photo) {
            guard let loader else { return }
            let image = await loader.image(for: photo, maxPixelSize: pixelSize)
            if !Task.isCancelled { loaded = image }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your try-on photo", bundle: .module, comment: "VoiceOver: her own try-on photo"))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("tryOnPhoto.own")
    }
}
