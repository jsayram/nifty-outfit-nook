import DesignSystem
import Models
import SwiftUI

/// What garment detail's buttons do. The screen fills these in; snapshot tests leave them empty.
struct GarmentDetailActions {
    var retry: () -> Void = {}
    var back: () -> Void = {}
    var openSuitcase: (Suitcase) -> Void = { _ in }
    var styleWithThis: () -> Void = {}
    var toggleLaundry: () -> Void = {}
    var addToSuitcase: () -> Void = {}
    var remove: () -> Void = {}
}

/// Garment detail's content, top to bottom (`garment.html`, with LR-10, LR-11 and LR-16):
/// her name for the piece, when she last wore it and the recent-wear note, "In suitcases:" with
/// each name as a button, the piece itself, Style with this and Mark as dirty, the facts, and a
/// quiet Remove from closet at the end.
///
/// Separate from `GarmentDetailScreen` so snapshot tests can draw it from a model.
struct GarmentDetailPage: View {
    let model: GarmentDetailModel
    var actions = GarmentDetailActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    /// Past this the page reads badly; iPad's own layout comes in Phase 15a.
    static let maximumWidth: CGFloat = 560

    var body: some View {
        if isStillImage {
            page
                .background(Color.nook.wallGradient)
        } else {
            ScrollView(.vertical) {
                page
            }
            .background(Color.nook.wallGradient.ignoresSafeArea())
        }
    }

    private var page: some View {
        content
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.top, NookSpacing.small)
            .padding(.bottom, NookSpacing.xxxLarge)
            .frame(maxWidth: Self.maximumWidth)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(
                String(localized: "Opening this piece", bundle: .module, comment: "Garment detail loading")
            )
            .padding(.top, NookSpacing.xxxLarge)
        case .failed:
            NookErrorState(
                String(localized: "This piece didn’t load", bundle: .module, comment: "Garment detail error title"),
                message: String(
                    localized: "Nothing was lost. Try again in a moment.", bundle: .module,
                    comment: "Closet error message"),
                retry: actions.retry
            )
            .padding(.top, NookSpacing.xxxLarge)
        case .gone:
            NookEmptyState(
                String(
                    localized: "This piece isn’t in your closet any more", bundle: .module,
                    comment: "Garment detail: the piece was deleted elsewhere"),
                message: String(
                    localized: "Deleted pieces stay in Recently deleted for 30 days.", bundle: .module,
                    comment: "Garment detail: where a deleted piece went"),
                systemImage: "hanger"
            ) {
                NookButton(
                    String(localized: "Back to Closet", bundle: .module, comment: "Button: goes back to Closet"),
                    systemImage: "chevron.left", kind: .soft, fillsWidth: true, action: actions.back
                )
                .accessibilityIdentifier("garment.gone.back")
            }
            .padding(.top, NookSpacing.xxxLarge)
        case .loaded:
            if let garment = model.garment, let text = model.text(calendar: calendar, locale: locale) {
                loaded(garment, text: text)
            }
        }
    }

    private func loaded(_ garment: Garment, text: GarmentDetailText) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GarmentDetailHeader(
                name: garment.name, text: text, suitcases: model.suitcases, openSuitcase: actions.openSuitcase)
            GarmentStage(garment: garment, isInTheWash: text.isInTheWash)
                .padding(.top, NookSpacing.small)
            if model.isInCloset {
                buttons(text)
                    .padding(.top, NookSpacing.medium)
            }
            GarmentFacts(text: text, savedLookCount: model.savedLooks.count, garment: garment)
                .padding(.top, NookSpacing.xLarge)
            if model.isInCloset {
                NookButton(
                    String(
                        localized: "Remove from closet", bundle: .module, comment: "Button on garment detail (LR-16)"),
                    systemImage: "trash", kind: .text, action: actions.remove
                )
                .accessibilityHint(
                    Text(
                        "Choose whether you don’t have it any more, or want to delete it.", bundle: .module,
                        comment: "Hint on Remove from closet")
                )
                .accessibilityIdentifier("garment.remove")
                .frame(maxWidth: .infinity)
                .padding(.top, NookSpacing.xLarge)
            }
        }
    }

    private func buttons(_ text: GarmentDetailText) -> some View {
        VStack(spacing: NookSpacing.medium) {
            NookButton(
                String(localized: "Style with this", bundle: .module, comment: "Button on garment detail"),
                systemImage: "sparkles", fillsWidth: true, action: actions.styleWithThis
            )
            .accessibilityHint(
                Text(
                    "Style Me with it, or make your own look with it.", bundle: .module,
                    comment: "Hint on Style with this")
            )
            .accessibilityIdentifier("garment.styleWithThis")
            NookButton(
                String(localized: "Add to a suitcase", bundle: .module, comment: "Button on garment detail (Phase 13)"),
                systemImage: "suitcase", kind: .soft, fillsWidth: true, action: actions.addToSuitcase
            )
            .accessibilityHint(
                Text(
                    "Choose the suitcases it’s packed in.", bundle: .module, comment: "Hint on Add to a suitcase")
            )
            .accessibilityIdentifier("garment.addToSuitcase")
            if model.showsLaundryAction {
                NookButton(
                    text.isInTheWash
                        ? String(localized: "Mark as clean", bundle: .module, comment: "Button on garment detail")
                        : String(localized: "Mark as dirty", bundle: .module, comment: "Button on garment detail"),
                    systemImage: text.isInTheWash ? "checkmark" : "basket", kind: .soft,
                    isLoading: model.isSaving, fillsWidth: true, action: actions.toggleLaundry
                )
                .accessibilityIdentifier("garment.laundry")
            }
        }
    }
}

/// The name, Last worn with its note (LR-10), and "In suitcases:" with a button per suitcase
/// (LR-11.4).
private struct GarmentDetailHeader: View {
    let name: String
    let text: GarmentDetailText
    let suitcases: [Suitcase]
    let openSuitcase: (Suitcase) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            Text(name)
                .nookTextStyle(.display)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("garment.name")
            Text(text.lastWorn)
                .nookTextStyle(.label)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("garment.lastWorn")
            if let note = text.recentWearNote {
                Label {
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .accessibilityHidden(true)
                }
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .accessibilityIdentifier("garment.recentWear")
            }
            if !suitcases.isEmpty {
                suitcaseLine
                    .padding(.top, NookSpacing.xSmall)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "In suitcases:" then a chip per suitcase, wrapping onto more lines as needed.
    private var suitcaseLine: some View {
        NookFlowLayout(spacing: NookSpacing.small, lineSpacing: 0) {
            Text("In suitcases:", bundle: .module, comment: "Garment detail, before the suitcases it's in (LR-11)")
                .nookTextStyle(.label)
                .foregroundStyle(.nook.textPrimary)
                .frame(minHeight: NookSpacing.minimumTapTarget)
            ForEach(suitcases) { suitcase in
                NookChip(suitcase.name, systemImage: "suitcase", isSelected: false) {
                    openSuitcase(suitcase)
                }
                .accessibilityLabel(
                    Text(
                        "In suitcase \(suitcase.name)", bundle: .module,
                        comment: "Spoken for a suitcase on garment detail, as in In suitcase Weekend")
                )
                .accessibilityHint(Text("Opens the suitcase.", bundle: .module, comment: "Hint on a suitcase name"))
                .accessibilityIdentifier("garment.suitcase.\(suitcase.id.rawValue)")
            }
        }
    }
}

/// The piece itself on a soft glow with its contact shadow, tilted a little like a sticker
/// (`.stage` in `garment.html`), with "In the wash" while tracking is on. Its picture comes from
/// the `ImageProvider` through the shared loader, at the size it's shown.
struct GarmentStage: View {
    let garment: Garment
    let isInTheWash: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A little smaller at the accessibility sizes, so the words that matter come sooner.
    private var pictureSize: CGSize {
        dynamicTypeSize.isAccessibilitySize ? CGSize(width: 150, height: 190) : CGSize(width: 190, height: 236)
    }

    var body: some View {
        let size = pictureSize
        ZStack {
            Ellipse()
                .fill(
                    EllipticalGradient(
                        colors: [Color.nook.tintStrong, Color.nook.tintStrong.opacity(0)], center: .center,
                        startRadiusFraction: 0, endRadiusFraction: 0.5)
                )
                .frame(width: size.width * 1.6, height: size.height * 1.12)
            GarmentContactShadow()
                .frame(width: size.width * 0.9, height: size.height * 0.1)
                .offset(y: size.height * 0.47)
            GarmentPicture(garment, size: size, presentation: .sticker(.resting))
                .rotationEffect(.degrees(-3))
        }
        .frame(maxWidth: .infinity)
        .frame(height: size.height * 1.12)
        .overlay(alignment: .topLeading) {
            if isInTheWash {
                NookBadge(
                    String(localized: "In the wash", bundle: .module, comment: "Mark on a piece that's dirty"),
                    systemImage: "basket", tone: .warning
                )
                .fixedSize()
            }
        }
        // The Status fact says the same in words, so VoiceOver skips the drawing.
        .accessibilityHidden(true)
    }
}
