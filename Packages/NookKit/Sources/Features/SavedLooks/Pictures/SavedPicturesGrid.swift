import DesignSystem
import Models
import SwiftUI

/// Her try-on pictures, newest first (RD-08, `saved.html` with `?tab=pictures`): each picture
/// with Simulated on it, the day it was made, and under it a link to the look it came from.
///
/// The picture and the link are separate buttons, as in the mockup: the picture opens picture
/// detail, the link opens the look (RD-08.2). Lazy, like the looks grid. Two or more columns of
/// at least 150 points; at the accessibility sizes one picture per row, beside its words.
///
/// In a wide window (Phase 15b) a picture opens beside the grid, and that picture stands on a
/// soft tint and reads as selected.
struct SavedPicturesGrid: View {
    let items: [SavedPictureItem]
    /// When the pictures loaded, for "Today" and "28 Aug".
    let now: Date
    /// The picture showing beside the grid.
    var current: TryOnPicture.ID?
    var opensBeside = false
    let open: (SavedPictureItem) -> Void
    let openLook: (Look) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.closetIsStillImage) private var isStillImage

    private var rows: some View {
        ForEach(items) { item in
            SavedPictureCell(
                item: item, now: now, style: .row, isCurrent: item.id == current, opensBeside: opensBeside,
                open: { open(item) }, openLook: openLook)
        }
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            if isStillImage {
                VStack(alignment: .leading, spacing: NookSpacing.large) { rows }
            } else {
                LazyVStack(alignment: .leading, spacing: NookSpacing.large) { rows }
            }
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 240), spacing: NookSpacing.medium, alignment: .top)
                ],
                spacing: NookSpacing.large
            ) {
                ForEach(items) { item in
                    SavedPictureCell(
                        item: item, now: now, style: .tile, isCurrent: item.id == current, opensBeside: opensBeside,
                        open: { open(item) }, openLook: openLook)
                }
            }
        }
    }
}

/// One picture: the picture (a button that opens it), the day it was made with a note when its
/// look changed or left, and the link to its look.
struct SavedPictureCell: View {
    enum Style {
        case tile
        case row
    }

    let item: SavedPictureItem
    let now: Date
    let style: Style
    /// Its detail is showing beside the grid (iPad, Phase 15b).
    var isCurrent = false
    var opensBeside = false
    let open: () -> Void
    let openLook: (Look) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    /// The picture's width in a row at the accessibility sizes.
    static let rowPictureWidth: CGFloat = 104

    var body: some View {
        cell
            .background { CurrentItemTint(isCurrent: isCurrent) }
    }

    @ViewBuilder private var cell: some View {
        switch style {
        case .tile:
            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                Button(action: open) {
                    Color.clear
                        .aspectRatio(TryOnPictureView.aspectRatio, contentMode: .fit)
                        .overlay {
                            GeometryReader { proxy in
                                TryOnPictureView(
                                    content: item.content, lookName: item.lookName, width: proxy.size.width)
                            }
                        }
                }
                .buttonStyle(PictureRowPressStyle())
                .modifier(
                    PictureButtonAccessibility(item: item, date: date, isCurrent: isCurrent, opensBeside: opensBeside)
                )
                .hoverEffect(.highlight)
                words
            }
        case .row:
            HStack(alignment: .top, spacing: NookSpacing.medium) {
                Button(action: open) {
                    TryOnPictureView(content: item.content, lookName: item.lookName, width: Self.rowPictureWidth)
                }
                .buttonStyle(PictureRowPressStyle())
                .modifier(
                    PictureButtonAccessibility(item: item, date: date, isCurrent: isCurrent, opensBeside: opensBeside)
                )
                .hoverEffect(.highlight)
                words
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var date: String {
        TryOnText.shortDate(item.picture.createdAt, now: now, calendar: calendar, locale: locale)
    }

    /// The day, a note, and the link to the look.
    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dateLine)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, NookSpacing.xxSmall)
                .accessibilityHidden(true)
            if let look = item.look {
                Button {
                    openLook(look)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: NookSpacing.xxSmall) {
                        Text(item.lookName)
                            .nookTextStyle(.label)
                            .foregroundStyle(.nook.accent)
                            .lineLimit(style == .tile ? 2 : nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.nook.accent)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, NookSpacing.xxSmall)
                    .frame(minHeight: NookSpacing.minimumTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PictureRowPressStyle())
                .accessibilityLabel(Text(TryOnText.seeTheLook(item.lookName)))
                .accessibilityIdentifier("savedLooks.picture.look.\(item.id)")
            } else {
                Text(item.lookName)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textSecondary)
                    .lineLimit(style == .tile ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NookSpacing.xxSmall)
                    .padding(.top, NookSpacing.xxSmall)
                    .accessibilityHidden(true)
            }
        }
    }

    /// "28 Aug", "28 Aug · Earlier version", "28 Aug · Look deleted". In a row the picture is
    /// too small for its Simulated badge, so the line starts with Simulated (RD-04.2).
    private var dateLine: String {
        var parts = style == .row ? [TryOnText.simulated, date] : [date]
        switch item.status {
        case .current: break
        case .changed: parts.append(TryOnText.earlierVersionShort)
        case .notSaved: parts.append(TryOnText.lookNotSavedShort)
        }
        return parts.joined(separator: " · ")
    }
}

/// The picture's button reads as the picture, when it was made and where its look is.
private struct PictureButtonAccessibility: ViewModifier {
    let item: SavedPictureItem
    let date: String
    let isCurrent: Bool
    let opensBeside: Bool

    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(TryOnText.spokenPicture(of: item.content, lookName: item.lookName, locale: locale))
            )
            .accessibilityValue(Text(value))
            .accessibilityHint(Text(opensBeside ? TryOnText.showBesideHint : TryOnText.openHint))
            .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("savedLooks.picture.\(item.id)")
    }

    private var value: String {
        switch item.status {
        case .current: date
        case .changed: [date, TryOnText.earlierVersionShort].joined(separator: ", ")
        case .notSaved: [date, TryOnText.lookNotSavedShort].joined(separator: ", ")
        }
    }
}
