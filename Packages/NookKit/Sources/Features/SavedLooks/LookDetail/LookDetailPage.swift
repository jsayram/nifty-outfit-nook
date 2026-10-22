import DesignSystem
import Models
import SwiftUI

/// What look detail's buttons do. The screen supplies them.
struct LookDetailActions {
    var wearToday: () -> Void = {}
    var swap: () -> Void = {}
    /// Swap it on a piece that left her closet (LR-16.4): Swap a piece, starting on that piece.
    var swapIt: (LookBundlePiece) -> Void = { _ in }
    var tryOn: () -> Void = {}
    var rename: () -> Void = {}
    var delete: () -> Void = {}
    var openPiece: (LookBundlePiece) -> Void = { _ in }
    var findOne: (LookBundlePiece) -> Void = { _ in }
    var retry: () -> Void = {}
    /// One of the look's try-on pictures (RD-08.2).
    var openPicture: (TryOnPicture.ID) -> Void = { _ in }
    /// Save look, on an earlier result she didn't save (LR-06.4).
    var saveLook: () -> Void = {}
}

/// Look detail's content, top to bottom (`look.html`): the name and its facts, the look large,
/// a kind note when pieces left her closet, Wear today, Swap a piece, Try it on and Rename, its
/// try-on pictures (each opens picture detail, RD-08.2), the pieces (each opens its garment), and
/// Delete look, quiet, at the end.
///
/// One readable column, or the column beside Saved Looks' grid on iPad (Phase 15b).
/// Separate from `LookDetailScreen` so snapshot tests can draw it without navigation.
struct LookDetailPage: View {
    let model: LookDetailModel
    var actions = LookDetailActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    /// 33a: with real try-on pictures there's nothing simulated to say.
    @Environment(\.services) private var services

    var body: some View {
        Group {
            if isStillImage {
                content
            } else {
                TourScrollReader {
                    ScrollView { content }
                }
            }
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
    }

    private var content: some View {
        VStack(spacing: NookSpacing.large) {
            switch model.phase {
            case .loading:
                NookLoadingState(SavedLooksText.loading)
            case .failed:
                NookErrorState(LookDetailText.failedTitle, message: SavedLooksText.failedMessage, retry: actions.retry)
            case .missing:
                NookEmptyState(
                    LookDetailText.missingTitle, message: LookDetailText.missingMessage, systemImage: "bookmark"
                )
                .accessibilityIdentifier("lookDetail.missing")
            case .loaded:
                if let content = model.content {
                    loaded(content)
                }
            }
        }
        .padding(.horizontal, NookSpacing.screenMargin)
        .padding(.top, NookSpacing.small)
        .padding(.bottom, NookSpacing.xxxLarge)
        .readablePane()
    }

    @ViewBuilder
    private func loaded(_ content: LookBundleContent) -> some View {
        if model.isEarlierResult {
            earlierResult(content)
        } else {
            saved(content)
        }
    }

    /// An earlier result she didn't save (LR-06.4, opened from search): the look, what it is,
    /// Save look, and its pieces. Nothing else changes it until it's saved.
    @ViewBuilder
    private func earlierResult(_ content: LookBundleContent) -> some View {
        header
        LookBundle(content, size: .large, title: model.name)
        VStack(spacing: NookSpacing.small) {
            Text(LookDetailText.earlierResultNote)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lookDetail.earlierNote")
            NookButton(LookDetailText.saveLook, systemImage: "heart", fillsWidth: true, action: actions.saveLook)
                .accessibilityIdentifier("lookDetail.saveLook")
        }
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            NookSectionHeader(LookDetailText.piecesHeading)
            LookPieceList(
                content: content, onFindOne: actions.findOne, onOpen: actions.openPiece, onSwapIt: actions.swapIt)
        }
    }

    @ViewBuilder
    private func saved(_ content: LookBundleContent) -> some View {
        header
        LookBundle(content, size: .large, title: model.name)
        if !content.removed.isEmpty {
            removedNote(content.removed)
        }
        buttons
        if !model.pictures.isEmpty {
            pictures
        }
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            NookSectionHeader(LookDetailText.piecesHeading)
            LookPieceList(
                content: content, onFindOne: actions.findOne, onOpen: actions.openPiece, onSwapIt: actions.swapIt)
            if model.goneCount > 0 {
                Text(LookDetailText.gone(model.goneCount))
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NookSpacing.small)
            }
        }
        NookButton(LookDetailText.delete, systemImage: "trash", kind: .text, action: actions.delete)
            .accessibilityHint(Text(LookDetailText.deleteHint))
            .accessibilityIdentifier("lookDetail.delete")
    }

    /// The look's try-on pictures, newest first: a small picture, "Try-on picture" and
    /// "Simulated · Made 28 Aug", each opening picture detail.
    private var pictures: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            NookSectionHeader(TryOnText.picturesHeading)
            ForEach(model.pictures) { picture in
                Button {
                    actions.openPicture(picture.id)
                } label: {
                    HStack(spacing: NookSpacing.medium) {
                        TryOnPictureView(
                            content: model.pictureContent(picture), lookName: model.name, width: Self.thumbnailWidth)
                        VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                            Text(TryOnText.pictureTitle)
                                .nookTextStyle(.label)
                                .foregroundStyle(.nook.textPrimary)
                            Text(model.pictureFacts(picture, locale: locale))
                                .nookTextStyle(.note)
                                .foregroundStyle(.nook.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.nook.chevron)
                            .accessibilityHidden(true)
                    }
                    .nookCard(.tint, padding: NookSpacing.small)
                }
                .buttonStyle(PictureRowPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(TryOnText.pictureTitle))
                .accessibilityValue(Text(model.pictureFacts(picture, locale: locale)))
                .accessibilityHint(Text(TryOnText.openHint))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("lookDetail.picture.\(picture.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A picture's width in the look's list of pictures.
    static let thumbnailWidth: CGFloat = 56

    /// The name, big, and the facts under it.
    private var header: some View {
        VStack(spacing: NookSpacing.xSmall) {
            Text(model.name)
                .nookTextStyle(.title)
                .foregroundStyle(.nook.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("lookDetail.name")
            Text(model.facts(locale: locale).joined(separator: " · "))
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lookDetail.facts")
        }
        .frame(maxWidth: .infinity)
    }

    /// A kind note when pieces left her closet: no warning colour, it's not a problem.
    private func removedNote(_ pieces: [LookBundlePiece]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
            Image(systemName: "sparkles")
                .foregroundStyle(.nook.accent)
                .accessibilityHidden(true)
            Text(LookDetailText.removedNote(pieces))
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .nookCard(.tint)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lookDetail.removedNote")
    }

    /// Wear today, Swap a piece, Try it on and Rename: two by two, one column at the
    /// accessibility sizes, as on results (RD-06.3).
    private var buttons: some View {
        VStack(spacing: NookSpacing.small) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: NookSpacing.small) {
                    wear
                    swap
                    tryOn
                    rename
                }
            } else {
                Grid(horizontalSpacing: NookSpacing.small, verticalSpacing: NookSpacing.small) {
                    GridRow {
                        wear
                        swap
                    }
                    GridRow {
                        tryOn
                        rename
                    }
                }
            }
            if services.tryOnPipeline == nil {
                Text(SharedText.tryOnPicturesSimulated)
                    .nookTextStyle(.finePrint)
                    .foregroundStyle(.nook.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var wear: some View {
        let worn = model.isWornToday
        return NookButton(
            worn ? LookDetailText.wornToday : LookDetailText.wearToday,
            systemImage: worn ? "checkmark.circle.fill" : "calendar.badge.checkmark",
            kind: worn ? .soft : .primary,
            fillsWidth: true,
            action: actions.wearToday
        )
        .accessibilityAddTraits(worn ? .isSelected : [])
        .accessibilityHint(Text(worn ? LookDetailText.wornTodayHint : LookDetailText.wearTodayHint))
        .accessibilityIdentifier("lookDetail.wearToday")
        .tourAnchor(LookTour.Anchor.wearToday, label: worn ? LookDetailText.wornToday : LookDetailText.wearToday) {
            actions.wearToday()
        }
    }

    private var swap: some View {
        NookButton(
            LookDetailText.swap, systemImage: "arrow.left.arrow.right", kind: .soft, fillsWidth: true,
            action: actions.swap
        )
        .accessibilityHint(
            Text(
                "Changes one piece, from your own. Nothing is sent.", bundle: .module,
                comment: "Hint on Swap a piece on a saved look")
        )
        .accessibilityIdentifier("lookDetail.swap")
        .tourAnchor(LookTour.Anchor.swap, label: LookDetailText.swap) { actions.swap() }
    }

    private var tryOn: some View {
        NookButton(LookDetailText.tryOn, systemImage: "camera", kind: .soft, fillsWidth: true, action: actions.tryOn)
            .accessibilityHint(
                Text(
                    "Makes a simulated picture of this look.", bundle: .module,
                    comment: "VoiceOver hint on Try it on")
            )
            .accessibilityIdentifier("lookDetail.tryOn")
    }

    private var rename: some View {
        NookButton(LookDetailText.rename, systemImage: "pencil", kind: .soft, fillsWidth: true, action: actions.rename)
            .accessibilityIdentifier("lookDetail.rename")
            .tourAnchor(LookTour.Anchor.rename, label: LookDetailText.rename) { actions.rename() }
    }
}
