import DesignSystem
import Models
import SwiftUI

/// The Saved tab (LR-06): looks she saved for this source and occasion, free to open. Unsaved
/// earlier results aren't listed (LR-06.4), and there's no Shuffle (LR-06.3).
///
/// In a regular-width window (iPad, Phase 15b) the looks fill the width as a grid, each bundle
/// on a soft mat with its name under it, as on Saved Looks; otherwise they're one list in a
/// readable column.
struct SavedLooksTab: View {
    let model: YourLooksModel
    let text: YourLooksText
    let actions: YourLooksActions

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The narrowest and widest column of saved looks in a wide window.
    static let tileWidths: ClosedRange<CGFloat> = 180...240

    private var fillsTheWidth: Bool {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: NookSpacing.medium) {
            if model.looksUnavailable {
                NookErrorState(
                    String(localized: "Saved looks didn’t load", bundle: .module, comment: "Saved tab error title"),
                    message: String(
                        localized: "Nothing was sent. Try again in a moment.", bundle: .module,
                        comment: "Your looks when the stores fail"),
                    retry: actions.reloadSaved)
            } else if model.savedLooks.isEmpty {
                NookEmptyState(text.savedEmptyTitle, message: text.savedEmptyMessage, systemImage: "heart")
                    .accessibilityIdentifier("results.saved.empty")
            } else {
                Text(text.savedLead)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if fillsTheWidth {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: Self.tileWidths.lowerBound, maximum: Self.tileWidths.upperBound),
                                spacing: NookSpacing.medium, alignment: .top)
                        ],
                        spacing: NookSpacing.large
                    ) {
                        ForEach(model.savedLooks) { look in
                            tile(look)
                        }
                    }
                } else {
                    VStack(spacing: NookSpacing.xSmall) {
                        ForEach(model.savedLooks) { look in
                            row(look)
                        }
                    }
                }
            }
        }
        .readablePane(maxWidth: fillsTheWidth ? WindowLayout.panesMaximumWidth : WindowLayout.readableWidth)
    }

    private func row(_ look: Look) -> some View {
        let content = LookBundleContent(look: look, garments: model.garments)
        let name = look.name ?? text.name(for: look, garments: model.garments)
        let detail = detail(for: look, content: content)
        return Button {
            actions.openSaved(look)
        } label: {
            HStack(spacing: NookSpacing.medium) {
                LookBundle(content, size: LookBundleSize(width: 70), title: name)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                    Text(name)
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                    Text(detail)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.nook.chevron)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, NookSpacing.small)
            .padding(.vertical, NookSpacing.small)
        }
        .buttonStyle(.nookRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LookBundleText.summary(of: content, title: name, locale: locale)))
        .accessibilityValue(Text(detail))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("results.saved.\(look.id)")
    }

    /// A look in the wide grid: its bundle on a soft mat, its name and detail under it. One
    /// VoiceOver button, like a row.
    private func tile(_ look: Look) -> some View {
        let content = LookBundleContent(look: look, garments: model.garments)
        let name = look.name ?? text.name(for: look, garments: model.garments)
        let detail = detail(for: look, content: content)
        return Button {
            actions.openSaved(look)
        } label: {
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                Color.clear
                    .aspectRatio(StickerBundleLayout.aspectRatio, contentMode: .fit)
                    .overlay {
                        GeometryReader { proxy in
                            LookBundle(content, size: LookBundleSize(width: proxy.size.width), title: name)
                        }
                    }
                    .padding(NookSpacing.small)
                    .background {
                        NookRadius.shape(NookRadius.tile)
                            .fill(Color.nook.tint)
                            .softShadow(.drop, in: NookRadius.shape(NookRadius.tile))
                    }
                VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                    Text(name)
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                    Text(detail)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, NookSpacing.xxSmall)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PictureRowPressStyle())
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LookBundleText.summary(of: content, title: name, locale: locale)))
        .accessibilityValue(Text(detail))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("results.saved.\(look.id)")
    }

    /// "4 pieces · Last worn 9 Oct".
    private func detail(for look: Look, content: LookBundleContent) -> String {
        var parts = [StyleMeText.pieces(content.pieces.count)]
        if let lastWorn = look.lastWorn {
            parts.append(
                LastWornText.describe(lastWorn, now: model.request.createdAt, calendar: calendar, locale: locale))
        }
        return parts.joined(separator: " · ")
    }
}

/// A saved look opened from the Saved tab: its bundle and pieces. Look detail, Wear today and
/// renaming come with Saved Looks (Phase 12a).
struct SavedLookSheet: View {
    let look: Look
    let garments: [Garment.ID: Garment]
    let findOne: (LookBundlePiece) -> Void

    var body: some View {
        let content = LookBundleContent(look: look, garments: garments)
        VStack(spacing: NookSpacing.medium) {
            LookBundle(content, size: .large, title: look.name)
            LookPieceList(content: content, onFindOne: findOne)
        }
        .frame(maxWidth: .infinity)
    }
}
