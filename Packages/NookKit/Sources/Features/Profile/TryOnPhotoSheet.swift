import DesignSystem
import SwiftUI

/// Your try-on photo (RD-06, PRD §9.2.1 step 1, `settings.html`'s photo sheet), Stage A.
///
/// The photo is the picture of her that real try-on pictures will start from (Phase 33). Here
/// the sheet explains what it's for and how it's kept, and offers an example in its place: no
/// camera, no photo library, no permission prompt and nothing uploaded. She can add the example,
/// change it and remove it, and removing never touches the try-on pictures she saved.
///
/// The example has no person in it, like Stage A's try-on pictures (Phase 12b). It is hidden in
/// the app switcher, as the real photo will be.
struct TryOnPhotoSheet: View {
    let hasPhoto: Bool
    /// Uses the example photo. Returns false when it wasn't saved.
    let useExample: () async -> Bool
    /// Removes the photo. Returns false when it wasn't saved.
    let remove: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.closetIsStillImage) private var isStillImage
    @State private var step: Step
    @State private var isSaving = false
    @State private var didFail = false
    @AccessibilityFocusState private var focusedStep: Step?

    enum Step: Hashable {
        case main
        /// "Choose example photo": what she'd pick, as an example.
        case example
        /// "Remove photo?"
        case remove
    }

    init(
        hasPhoto: Bool, step: Step = .main, useExample: @escaping () async -> Bool,
        remove: @escaping () async -> Bool
    ) {
        self.hasPhoto = hasPhoto
        self.useExample = useExample
        self.remove = remove
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            switch step {
            case .main: main
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
    }

    // MARK: Steps

    private var main: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            lead(
                String(
                    localized:
                        "This is the photo of you that try-on pictures will start from, once they’re ready. It’s optional: styling never needs it.",
                    bundle: .module, comment: "Try-on photo sheet: what the photo is for"),
                step: .main)
            if hasPhoto {
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
            privacyPoints
            VStack(spacing: NookSpacing.small) {
                NookButton(
                    hasPhoto
                        ? String(
                            localized: "Change example photo", bundle: .module, comment: "Try-on photo sheet button")
                        : String(
                            localized: "Choose example photo", bundle: .module, comment: "Try-on photo sheet button"),
                    systemImage: "photo", fillsWidth: true
                ) {
                    step = .example
                }
                .accessibilityIdentifier("tryOnPhoto.choose")
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
            Text(
                "This test build uses an example photo. It doesn’t ask for your camera or your photos, and nothing is uploaded.",
                bundle: .module, comment: "Try-on photo sheet: Stage A note"
            )
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

/// Stage A's example try-on photo: the try-on backdrop with a photo symbol and "Example photo ·
/// Simulated". It isn't a person and isn't her. Hidden in the app switcher like a real photo.
struct ExamplePhoto: View {
    static let size = CGSize(width: 168, height: 210)

    var body: some View {
        let shape = NookRadius.shape(NookRadius.tile)
        VStack(spacing: NookSpacing.small) {
            ZStack {
                LinearGradient(colors: [.nook.artStone, .nook.artSand], startPoint: .top, endPoint: .bottom)
                Image(systemName: "photo")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.nook.textSecondary)
                NookBadge(TryOnText.simulated, systemImage: "camera")
                    .padding(NookSpacing.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(shape)
            .background {
                shape
                    .fill(Color.nook.tint)
                    .softShadow(.drop, in: shape)
            }
            .hiddenWhenInactive()
            Text("Example photo · Simulated", bundle: .module, comment: "Under the example try-on photo")
                .nookTextStyle(.caption)
                .foregroundStyle(.nook.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                "Example try-on photo, simulated. It isn’t a photo of you.", bundle: .module,
                comment: "VoiceOver: the example try-on photo")
        )
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("tryOnPhoto.example")
    }
}
