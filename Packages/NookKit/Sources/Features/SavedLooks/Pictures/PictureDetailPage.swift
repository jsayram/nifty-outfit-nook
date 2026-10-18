import DesignSystem
import Models
import SwiftUI

/// What picture detail's buttons do. The screen supplies them.
struct PictureDetailActions {
    var seeLook: (Look) -> Void = { _ in }
    var delete: () -> Void = {}
    var retry: () -> Void = {}
}

/// Picture detail, top to bottom (`picture.html`): Try-on picture and "Simulated · Made 28 Aug",
/// the picture large, the look it came from (See the look), a note when the look changed or
/// left, Delete picture, and what a simulated picture is.
///
/// The mockup's Favorite has no Stage A screen (RD-08), and its delete confirmation is replaced
/// by Undo, as Delete look does (Phase 12a).
///
/// One readable column, or the column beside the Pictures grid on iPad (Phase 15b). Separate from
/// `PictureDetailScreen` so snapshot tests can draw it without navigation.
struct PictureDetailPage: View {
    let model: PictureDetailModel
    var actions = PictureDetailActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.locale) private var locale

    /// The picture's width on the page.
    static let pictureWidth: CGFloat = 280

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
                NookLoadingState(TryOnText.loading)
            case .failed:
                NookErrorState(TryOnText.failedTitle, message: SavedLooksText.failedMessage, retry: actions.retry)
            case .missing:
                NookEmptyState(
                    PictureDetailText.missingTitle, message: PictureDetailText.missingMessage, systemImage: "photo"
                )
                .accessibilityIdentifier("picture.missing")
            case .loaded:
                if let item = model.item {
                    loaded(item)
                }
            }
        }
        .padding(.horizontal, NookSpacing.screenMargin)
        .padding(.top, NookSpacing.small)
        .padding(.bottom, NookSpacing.xxxLarge)
        .readablePane()
    }

    @ViewBuilder
    private func loaded(_ item: SavedPictureItem) -> some View {
        header
        TryOnPictureView(content: item.content, lookName: item.lookName, width: Self.pictureWidth)
            .accessibilityIdentifier("picture.image")
        lookLink(item)
        NookButton(TryOnText.delete, systemImage: "trash", kind: .text, action: actions.delete)
            .accessibilityHint(Text(TryOnText.deleteHint))
            .accessibilityIdentifier("picture.delete")
            .tourAnchor(PictureTour.Anchor.delete, label: TryOnText.delete) { actions.delete() }
        about(showsPerson: item.content.tryOnPhoto != nil)
    }

    private var header: some View {
        VStack(spacing: NookSpacing.xSmall) {
            Text(TryOnText.pictureTitle)
                .nookTextStyle(.title)
                .foregroundStyle(.nook.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("picture.title")
            Text(model.facts(locale: locale))
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("picture.facts")
        }
        .frame(maxWidth: .infinity)
    }

    /// The look it came from: a row that opens it while it's in Saved Looks, with a note when it
    /// changed since; just the note once it has left.
    @ViewBuilder
    private func lookLink(_ item: SavedPictureItem) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            if let look = item.look {
                Button {
                    actions.seeLook(look)
                } label: {
                    lookRow(item, opens: true)
                }
                .buttonStyle(PictureRowPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(TryOnText.seeTheLook(item.lookName)))
                .accessibilityValue(Text(item.look?.occasion?.title ?? ""))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("picture.seeLook")
                .tourAnchor(PictureTour.Anchor.seeLook, label: TryOnText.seeTheLook(item.lookName)) {
                    actions.seeLook(look)
                }
            } else {
                lookRow(item, opens: false)
                    .accessibilityElement(children: .combine)
            }
            if let note = model.linkNote {
                Text(note)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NookSpacing.small)
                    .accessibilityIdentifier("picture.linkNote")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lookRow(_ item: SavedPictureItem, opens: Bool) -> some View {
        HStack(spacing: NookSpacing.medium) {
            LookBundle(item.lookContent, size: .small, title: item.lookName)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                Text(TryOnText.fromTheLook)
                    .nookTextStyle(.caption)
                    .foregroundStyle(.nook.textSecondary)
                Text(item.lookName)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if opens {
                    Text(TryOnText.seeTheLook)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.accent)
                } else {
                    Text(TryOnText.lookNotSavedShort)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if opens {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.nook.chevron)
                    .accessibilityHidden(true)
            }
        }
        .nookCard(.tint, padding: NookSpacing.medium)
    }

    /// What a simulated picture is, on a soft tint.
    private func about(showsPerson: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
            Image(systemName: "info.circle")
                .foregroundStyle(.nook.accent)
                .accessibilityHidden(true)
            Text(TryOnText.aboutSimulated(showsPerson: showsPerson))
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .nookCard(.tint)
        .accessibilityElement(children: .combine)
    }
}

/// A soft dim while pressed, with no outline.
struct PictureRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// The words only picture detail uses.
enum PictureDetailText {
    static var missingTitle: String {
        String(localized: "This picture was deleted", bundle: .module, comment: "Picture detail: picture gone")
    }

    static var missingMessage: String {
        String(
            localized: "The look it came from didn’t change.", bundle: .module, comment: "Picture detail: picture gone")
    }
}
