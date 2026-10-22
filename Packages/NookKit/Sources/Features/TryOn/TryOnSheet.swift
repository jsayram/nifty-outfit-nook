import DesignSystem
import Models
import SwiftUI

/// Try it on, open in a sheet. Pushed by identity: each opening is a new start.
struct TryOnRoute: Identifiable, Hashable {
    let id = UUID()
    let model: TryOnModel

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension View {
    /// The Try it on sheet: titled Try it on, with Simulated under the title, full height.
    func tryOnSheet(
        _ route: Binding<TryOnRoute?>, seePicture: @escaping (TryOnPicture) -> Void
    ) -> some View {
        nookSheet(
            item: route,
            title: { _ in TryOnText.tryOn },
            subtitle: { _ in SharedText.simulated },
            // Full height: the picture and its two buttons don't fit a half-height sheet.
            detents: [.large],
            content: { route in TryOnSheetContent(model: route.model, seePicture: seePicture) }
        )
    }
}

/// What the Try it on sheet shows at each step (`TryOnModel`): what will happen, a picture she
/// already has, making it, the picture, or what went wrong.
///
/// Before anything is made it says, in plain words, that the picture is simulated in this build
/// and shows either the person in her try-on photo wearing the look or her pieces alone; that it's free here (pictures will use an allowance later, PRD
/// §14.4, but there's no purchase screen in Stage A); and, from Your looks, that the look gets
/// saved too.
struct TryOnSheetContent: View {
    let model: TryOnModel
    let seePicture: (TryOnPicture) -> Void

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    /// 30a: Styling access, when pictures need it.
    @State private var showsStylingAccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            switch model.step {
            case .ready: ready
            case .alreadyMade(let picture): alreadyMade(picture)
            case .making: making
            case .made(let picture): made(picture)
            case .failed(let failure): failed(failure)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.default, value: model.step)
        .task { await model.start(with: services) }
        .onDisappear { model.cancel() }
        .sheet(isPresented: $showsStylingAccess, onDismiss: { Task { await model.start(with: services) } }) {
            NavigationStack {
                StylingAccessScreen(isSheet: true)
            }
        }
        .onChange(of: model.step) { _, step in
            if case .made = step {
                AccessibilityNotification.Announcement(TryOnSheetText.madeTitle).post()
            }
        }
        // The sheet's quick tour (Stage A audit), before anything is made. The sheet draws it.
        .screenTour(TryOnTour.definition, isReady: model.step == .ready)
    }

    // MARK: Steps

    private var ready: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                line(TryOnSheetText.what, systemImage: "camera")
                line(TryOnSheetText.simulatedHere, systemImage: "sparkles")
            }
            .tourAnchor(TryOnTour.Anchor.about, label: TryOnSheetText.what)
            if model.savesLook {
                line(TryOnSheetText.savesTheLook, systemImage: "heart")
            }
            switch model.allowance {
            case .freeSimulated:
                note(TryOnSheetText.free)
            case .included(let perMonth):
                note(TryOnSheetText.included(perMonth))
            case .needsStylingAccess:
                note(TryOnSheetText.needsAccess)
            }
            if model.allowance == .needsStylingAccess {
                NookButton(
                    TryOnSheetText.seeStylingAccess, systemImage: "sparkles", fillsWidth: true
                ) { showsStylingAccess = true }
                .accessibilityIdentifier("tryOn.stylingAccess")
            } else {
                NookButton(TryOnSheetText.make, systemImage: "camera", fillsWidth: true, action: model.make)
                    .accessibilityIdentifier("tryOn.make")
                    .tourAnchor(TryOnTour.Anchor.make, label: TryOnSheetText.make, action: model.make)
            }
        }
        // A container keeps its children's own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tryOn.ready")
    }

    private func alreadyMade(_ picture: TryOnPicture) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            picturePreview(picture)
            Text(TryOnSheetText.alreadyMadeTitle)
                .nookTextStyle(.headline)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(TryOnSheetText.alreadyMadeMessage)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NookButton(TryOnSheetText.seePicture, systemImage: "photo", fillsWidth: true) { open(picture) }
                .accessibilityIdentifier("tryOn.seeExisting")
            NookButton(TryOnSheetText.makeAnother, systemImage: "camera", kind: .soft, fillsWidth: true) {
                model.make()
            }
            .accessibilityIdentifier("tryOn.makeAnother")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tryOn.alreadyMade")
    }

    private var making: some View {
        VStack(spacing: NookSpacing.large) {
            NookLoadingState(TryOnSheetText.makingTitle, message: TryOnSheetText.makingMessage)
            NookButton(TryOnSheetText.cancel, kind: .soft, fillsWidth: true, action: model.cancel)
                .accessibilityIdentifier("tryOn.cancel")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tryOn.making")
    }

    private func made(_ picture: TryOnPicture) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            picturePreview(picture)
            Label {
                Text(TryOnSheetText.madeTitle)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.nook.success)
            }
            .nookTextStyle(.headline)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("tryOn.made")
            NookButton(TryOnSheetText.seePicture, systemImage: "photo", fillsWidth: true) { open(picture) }
                .accessibilityIdentifier("tryOn.seePicture")
            NookButton(TryOnSheetText.done, kind: .soft, fillsWidth: true) { dismiss() }
                .accessibilityIdentifier("tryOn.done")
        }
    }

    private func failed(_ failure: TryOnModel.Failure) -> some View {
        NookErrorState(
            TryOnSheetText.failedTitle(failure), message: TryOnSheetText.failedMessage(failure), retry: model.make
        )
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("tryOn.failed")
    }

    // MARK: Parts

    private func picturePreview(_ picture: TryOnPicture) -> some View {
        TryOnPictureView(
            content: LookBundleContent(picture: picture, garments: model.garments), lookName: model.lookName,
            width: 200
        )
        .frame(maxWidth: .infinity)
    }

    private func line(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(.nook.accent)
                .accessibilityHidden(true)
            Text(text)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A quiet note on a tint, not the warning colour: nothing is wrong.
    private func note(_ text: String) -> some View {
        Text(text)
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nookCard(.tint)
            .accessibilityIdentifier("tryOn.free")
    }

    private func open(_ picture: TryOnPicture) {
        dismiss()
        seePicture(picture)
    }
}

/// The words on the Try it on sheet.
enum TryOnSheetText {
    static var what: String {
        String(
            localized: "Try it on makes one picture of this look, only now that you ask.", bundle: .module,
            comment: "Try it on sheet")
    }

    static var simulatedHere: String {
        String(
            localized:
                "In this test build the picture is simulated: the person in your try-on photo wearing the look, or your pieces on their own. Nothing leaves your phone.",
            bundle: .module, comment: "Try it on sheet")
    }

    static var savesTheLook: String {
        String(
            localized: "Making a picture also saves this look, so the picture has a look to go with.",
            bundle: .module, comment: "Try it on sheet, from Your looks for a look that isn't saved")
    }

    /// 30a: a picture uses one of the month's pictures that come with styling access.
    static func included(_ perMonth: Int) -> String {
        String(
            localized: "Uses 1 of the \(perMonth) try-on pictures that come with styling access each month.",
            bundle: .module, comment: "Try it on sheet: with styling access. The argument is a number.")
    }

    /// 30a: pictures need styling access, which she doesn't have now.
    static var needsAccess: String {
        String(
            localized: "Try-on pictures come with styling access. Your saved pictures stay free to open.",
            bundle: .module, comment: "Try it on sheet: without styling access")
    }

    static var seeStylingAccess: String {
        String(localized: "See styling access", bundle: .module, comment: "Try it on sheet button")
    }

    /// PRD §14.4: pictures use an allowance, except simulated ones, which cost nothing (30a).
    static var free: String {
        String(
            localized: "Simulated pictures are free in this test build.", bundle: .module,
            comment: "Try it on sheet: no picture allowance is used")
    }

    static var make: String {
        String(localized: "Make a picture", bundle: .module, comment: "Try it on sheet button")
    }

    static var makeAnother: String {
        String(localized: "Make another", bundle: .module, comment: "Try it on sheet button")
    }

    static var alreadyMadeTitle: String {
        String(
            localized: "You already have a picture of this look", bundle: .module,
            comment: "Try it on sheet: a picture of exactly this look exists (FR-59)")
    }

    static var alreadyMadeMessage: String {
        String(
            localized: "Seeing it again doesn’t make a new one.", bundle: .module,
            comment: "Try it on sheet: a picture of exactly this look exists (FR-59)")
    }

    static var makingTitle: String {
        String(localized: "Making a picture", bundle: .module, comment: "Try it on sheet, while making")
    }

    static var makingMessage: String {
        String(
            localized: "Simulated. Leaving stops it, and nothing is kept.", bundle: .module,
            comment: "Try it on sheet, while making")
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Button: stops making a picture")
    }

    static var madeTitle: String {
        String(localized: "Saved to Pictures", bundle: .module, comment: "Try it on sheet: the picture is ready")
    }

    static var seePicture: String {
        String(localized: "See the picture", bundle: .module, comment: "Button: opens a try-on picture")
    }

    static var done: String {
        String(localized: "Done", bundle: .module, comment: "Button: closes the Try it on sheet")
    }

    static func failedTitle(_ failure: TryOnModel.Failure) -> String {
        switch failure {
        case .offline:
            String(localized: "Pictures need a connection", bundle: .module, comment: "Try it on sheet: offline")
        case .notCompleted:
            String(localized: "The picture didn’t finish", bundle: .module, comment: "Try it on sheet: failed")
        case .notSaved:
            String(localized: "The picture couldn’t be kept", bundle: .module, comment: "Try it on sheet: not saved")
        }
    }

    static func failedMessage(_ failure: TryOnModel.Failure) -> String {
        switch failure {
        case .offline:
            String(
                localized: "Nothing was made or used. Try again when you’re online.", bundle: .module,
                comment: "Try it on sheet: offline")
        case .notCompleted, .notSaved:
            String(
                localized: "Nothing was used. Try again in a moment.", bundle: .module,
                comment: "Try it on sheet: failed")
        }
    }
}
