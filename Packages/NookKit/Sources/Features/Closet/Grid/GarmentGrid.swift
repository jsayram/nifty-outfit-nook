import DesignSystem
import Models
import SwiftUI

/// Her pieces, standing on the floor (`.grid` in `closet.html`): no cards, a soft shadow under
/// each piece and its name below.
///
/// Lazy, so a closet of thousands only builds the cells on screen. Each cell's details were
/// worked out when the closet loaded (`ClosetItem`), and its picture is a cheap drawing or a
/// cached, downsampled photo. Columns follow the width and the text size: as many 104 point
/// columns as fit, 150 point columns at the first accessibility sizes, and one piece per row,
/// with the name beside it, from AX3 up so long names never break mid-word.
struct GarmentGrid: View {
    let items: [ClosetItem]
    /// When the closet loaded, for "Last worn 3 days ago".
    let now: Date
    /// What tapping a piece does, for VoiceOver. `nil` says it opens the piece.
    var hint: String?
    /// The start of each cell's UI test identifier.
    var identifierPrefix = "closet.garment"
    /// Picking several (the packing sheet, Phase 13): the ticked pieces. `nil` for none.
    var selection: Set<Garment.ID>?
    /// A small minus on each piece that takes it out (a suitcase's pieces, Phase 13), with
    /// VoiceOver's words for it. `nil` for none.
    var remove: GarmentRemoveAction?
    let open: (ClosetItem) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch GarmentGridLayout(dynamicTypeSize) {
        case .rows:
            LazyVStack(alignment: .leading, spacing: NookSpacing.large) {
                ForEach(items) { item in
                    cell(item, style: .row)
                }
            }
        case .grid(let minimum):
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minimum), spacing: NookSpacing.small, alignment: .top)],
                spacing: 14
            ) {
                ForEach(items) { item in
                    cell(item, style: .tile)
                }
            }
        }
    }

    private func cell(_ item: ClosetItem, style: GarmentCell.Style) -> some View {
        GarmentCell(
            item: item, now: now, style: style, hint: hint, identifierPrefix: identifierPrefix,
            isSelected: selection.map { $0.contains(item.id) }, remove: remove
        ) {
            open(item)
        }
    }
}

/// How the grid lays out for a text size.
nonisolated enum GarmentGridLayout: Equatable {
    /// Columns at least this wide, as many as fit.
    case grid(minimumColumnWidth: CGFloat)
    /// One piece per row, picture beside the name.
    case rows

    init(_ size: DynamicTypeSize) {
        if size >= .accessibility3 {
            self = .rows
        } else if size.isAccessibilitySize {
            self = .grid(minimumColumnWidth: 150)
        } else {
            self = .grid(minimumColumnWidth: 104)
        }
    }

    /// The picture's size in points.
    var pictureSize: CGSize {
        switch self {
        case .grid(let minimum) where minimum < 150: CGSize(width: 70, height: 90)
        default: CGSize(width: 92, height: 120)
        }
    }
}

/// The minus on each piece of a suitcase (Phase 13): its VoiceOver label and what it does.
struct GarmentRemoveAction {
    /// "Remove Navy dress pants from Weekend".
    let label: (ClosetItem) -> String
    let action: (ClosetItem) -> Void
}

/// One piece: its picture on a soft shadow, the name under it (or beside it in rows), a tiny
/// suitcase when it's packed (LR-11) and Dirty while tracking is on (RD-11). One VoiceOver
/// button: "Navy dress pants", then "In Jose's house and Weekend, Last worn 5 days ago".
struct GarmentCell: View {
    enum Style {
        case tile
        case row
    }

    let item: ClosetItem
    let now: Date
    let style: Style
    var hint: String?
    var identifierPrefix = "closet.garment"
    /// Ticked or not, when the grid picks several. `nil` when it doesn't.
    var isSelected: Bool?
    var remove: GarmentRemoveAction?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        Button(action: action) {
            switch style {
            case .tile:
                VStack(spacing: 5) {
                    picture
                    name
                        .multilineTextAlignment(.center)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, NookSpacing.xSmall)
            case .row:
                HStack(alignment: .center, spacing: NookSpacing.medium) {
                    picture
                    name
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(ClosetPressStyle())
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(Text(item.spokenDetails(now: now, calendar: calendar, locale: locale)))
        .accessibilityHint(
            hint.map { Text($0) } ?? Text("Opens the piece.", bundle: .module, comment: "Hint on a closet piece")
        )
        .accessibilityAddTraits(isSelected == true ? [.isSelected] : [])
        .accessibilityIdentifier("\(identifierPrefix).\(item.id.rawValue)")
        .overlay(alignment: .topTrailing) {
            if let remove {
                Button {
                    remove.action(item)
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.nook.accent)
                        .frame(width: 26, height: 26)
                        .background {
                            Circle().fill(Color.nook.tintStrong)
                                .softShadow(.drop, in: Circle())
                        }
                        .frame(width: NookSpacing.minimumTapTarget, height: NookSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ClosetPressStyle())
                .offset(x: NookSpacing.small, y: -NookSpacing.small)
                .accessibilityLabel(Text(remove.label(item)))
                .accessibilityIdentifier("\(identifierPrefix).\(item.id.rawValue).remove")
            }
        }
    }

    private var size: CGSize { GarmentGridLayout(dynamicTypeSize).pictureSize }

    private var picture: some View {
        ZStack(alignment: .bottom) {
            GarmentContactShadow()
                .frame(width: size.width + 2, height: size.height * 0.15)
                .offset(y: size.height * 0.06)
            GarmentPicture(
                photo: item.photo, cutout: item.cutout, category: item.category, colors: item.colors, size: size)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topTrailing) {
            if let isSelected {
                SelectionTick(isSelected: isSelected)
                    .offset(x: NookSpacing.small, y: -NookSpacing.xSmall)
            }
        }
        .overlay(alignment: .topLeading) {
            if item.isDirty {
                NookBadge(
                    String(localized: "Dirty", bundle: .module, comment: "Badge on a closet piece in the wash"),
                    systemImage: "basket", tone: .warning
                )
                .fixedSize()
                .offset(x: -NookSpacing.small, y: -NookSpacing.xSmall)
            }
        }
        // At the piece's feet, so it never covers the Dirty badge and sits on the floor with
        // shoes and bags too.
        .overlay(alignment: .bottomTrailing) {
            if item.isPacked {
                PackedMark()
                    .offset(x: NookSpacing.small, y: NookSpacing.xxSmall)
            }
        }
        .accessibilityHidden(true)
    }

    private var name: some View {
        VStack(alignment: style == .tile ? .center : .leading, spacing: 3) {
            Text(item.name)
                .nookTextStyle(.chip)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = item.note {
                NookBadge(note, tone: .neutral)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The round tick on a piece in a grid that picks several: a solid accent circle with a check
/// when it's picked, an empty ring when it isn't. VoiceOver hears Selected from the cell.
struct SelectionTick: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle().fill(isSelected ? Color.nook.accent : Color.nook.tintStrong)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.nook.onAccent)
            } else {
                Circle().strokeBorder(Color.nook.chevron, lineWidth: 2)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

/// The tiny suitcase on a packed piece (LR-11): an icon only, no words. VoiceOver reads the
/// suitcase names from the cell instead.
private struct PackedMark: View {
    @ScaledMetric(relativeTo: .caption2) private var scaledSize: CGFloat = 22

    /// Grows a little with the text, but never enough to cover the piece at AX5.
    private var size: CGFloat { min(scaledSize, 28) }

    var body: some View {
        Image(systemName: "suitcase.fill")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.nook.accent)
            .frame(width: size, height: size)
            .background(Color.nook.tintStrong, in: Circle())
    }
}
