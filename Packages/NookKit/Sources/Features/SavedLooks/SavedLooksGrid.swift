import DesignSystem
import Models
import SwiftUI

/// Her saved looks, each as its sticker bundle on a soft cream mat with its name and occasion
/// under it (RD-08, `saved.html`): no frames or outlines, separated by space.
///
/// Lazy, so hundreds of looks only build the cells on screen. Each cell's bundle and words were
/// worked out when the looks loaded (`SavedLookItem`), and a bundle is a few cached stickers or
/// drawings, so scrolling stays cheap. Two or more columns of at least 150 points; at the
/// accessibility sizes one look per row, the bundle beside its name.
struct SavedLooksGrid: View {
    let items: [SavedLookItem]
    /// When the looks loaded, for "Last worn 3 days ago".
    let now: Date
    let open: (SavedLookItem) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.closetIsStillImage) private var isStillImage

    private var rows: some View {
        ForEach(items) { item in
            SavedLookCell(item: item, now: now, style: .row) { open(item) }
        }
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            if isStillImage {
                // A still image measures a lazy stack from estimates and cuts it off, so it draws
                // a plain one.
                VStack(alignment: .leading, spacing: NookSpacing.medium) { rows }
            } else {
                LazyVStack(alignment: .leading, spacing: NookSpacing.medium) { rows }
            }
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 240), spacing: NookSpacing.medium, alignment: .top)
                ],
                spacing: NookSpacing.large
            ) {
                ForEach(items) { item in
                    SavedLookCell(item: item, now: now, style: .tile) { open(item) }
                }
            }
        }
    }
}

/// One saved look: one VoiceOver button that names the look and its pieces, then the occasion,
/// when it was last worn and any piece that left her closet.
struct SavedLookCell: View {
    enum Style {
        case tile
        case row
    }

    let item: SavedLookItem
    let now: Date
    let style: Style
    let action: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    /// The bundle's width in a row at the accessibility sizes.
    static let rowBundleWidth: CGFloat = 96

    var body: some View {
        Button(action: action) {
            switch style {
            case .tile:
                VStack(alignment: .leading, spacing: NookSpacing.small) {
                    mat {
                        // The bundle takes the mat's width, keeping its shape.
                        Color.clear
                            .aspectRatio(StickerBundleLayout.aspectRatio, contentMode: .fit)
                            .overlay {
                                GeometryReader { proxy in
                                    LookBundle(item.content, size: LookBundleSize(width: proxy.size.width))
                                }
                            }
                            .padding(NookSpacing.small)
                    }
                    words
                }
            case .row:
                HStack(alignment: .center, spacing: NookSpacing.medium) {
                    mat {
                        LookBundle(item.content, size: LookBundleSize(width: Self.rowBundleWidth))
                            .padding(NookSpacing.xSmall)
                    }
                    words
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(SavedLookPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LookBundleText.summary(of: item.content, title: item.name, locale: locale)))
        .accessibilityValue(Text(SavedLooksText.spokenDetail(of: item, lastWorn: lastWorn)))
        .accessibilityHint(Text(SavedLooksText.openHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("savedLooks.look.\(item.id)")
    }

    private var lastWorn: String? {
        item.look.lastWorn.map { LastWornText.describe($0, now: now, calendar: calendar, locale: locale) }
    }

    private func mat(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: style == .tile ? .infinity : nil)
            .background {
                NookRadius.shape(NookRadius.tile)
                    .fill(Color.nook.tint)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.tile))
            }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
            Text(item.name)
                .nookTextStyle(.label)
                .foregroundStyle(.nook.textPrimary)
                .lineLimit(style == .tile ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .lineLimit(style == .tile ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, NookSpacing.xxSmall)
    }

    /// "Office · Last worn 5 days ago".
    private var detail: String? {
        let parts = [item.occasion, lastWorn].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A soft dim while pressed, with no outline.
private struct SavedLookPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}
