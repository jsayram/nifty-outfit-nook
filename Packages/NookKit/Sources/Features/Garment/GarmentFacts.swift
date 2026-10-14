import DesignSystem
import Models
import SwiftUI

/// The facts about a piece (`.facts` in `garment.html`): what it is, its colours, fit, seasons,
/// occasions, brand and size, whether she can wear it now, the saved looks that use it, and her
/// notes. Rows have no boxes and no lines between them (RD-05); unknown facts are left out.
struct GarmentFacts: View {
    let text: GarmentDetailText
    let savedLookCount: Int
    let garment: Garment

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NookSection(String(localized: "Details", bundle: .module, comment: "Garment detail: heading over the facts")) {
            GarmentFactRow(
                systemImage: "tag", label: String(localized: "Kind", bundle: .module, comment: "Garment fact label"),
                value: text.kind, identifier: "kind")
            if text.colors != nil || text.colorNote != nil {
                GarmentFactRow(
                    systemImage: "paintpalette",
                    label: String(localized: "Colour", bundle: .module, comment: "Garment fact label"),
                    value: text.colors ?? text.colorNote ?? "",
                    detail: text.colors == nil ? nil : text.colorNote,
                    swatches: garment.colors.map(swatch), identifier: "colour")
            }
            if let fit = text.fit {
                GarmentFactRow(
                    systemImage: "ruler",
                    label: String(localized: "Fit", bundle: .module, comment: "Garment fact label: how it's cut"),
                    value: fit, identifier: "fit")
            }
            if let seasons = text.seasons {
                GarmentFactRow(
                    systemImage: "leaf",
                    label: String(localized: "Seasons", bundle: .module, comment: "Garment fact label"),
                    value: seasons, identifier: "seasons")
            }
            if let occasions = text.occasions {
                GarmentFactRow(
                    systemImage: "calendar",
                    label: String(localized: "Occasions", bundle: .module, comment: "Garment fact label"),
                    value: occasions, identifier: "occasions")
            }
            if let brand = text.brand {
                GarmentFactRow(
                    systemImage: "storefront",
                    label: String(localized: "Brand", bundle: .module, comment: "Garment fact label"),
                    value: brand, identifier: "brand")
            }
            if let size = text.size {
                GarmentFactRow(
                    systemImage: "textformat.size",
                    label: String(localized: "Size", bundle: .module, comment: "Garment fact label: size on the label"),
                    value: size, identifier: "size")
            }
            GarmentFactRow(
                systemImage: "checkmark.circle",
                label: String(localized: "Status", bundle: .module, comment: "Garment fact label"),
                value: text.status, identifier: "status")
            GarmentFactRow(
                systemImage: "bookmark",
                label: String(localized: "Saved looks", bundle: .module, comment: "Garment fact label"),
                value: text.savedLooks(savedLookCount), identifier: "savedLooks")
            if let notes = text.notes {
                GarmentFactRow(
                    systemImage: "note.text",
                    label: String(localized: "Notes", bundle: .module, comment: "Garment fact label: her own notes"),
                    value: notes, identifier: "notes")
            }
        }
    }

    private func swatch(_ color: ColorName) -> Color {
        if color == .multicolor {
            return GarmentColor.multicolorStripes[0].color(in: colorScheme)
        }
        return GarmentColor.fill(for: color).color(in: colorScheme)
    }
}

/// One fact: an icon in a soft circle, the label, and the value at the end. At the accessibility
/// sizes the value moves under the label so long values wrap between words. One VoiceOver
/// element: "Fit, Relaxed".
struct GarmentFactRow: View {
    let systemImage: String
    let label: String
    let value: String
    var detail: String?
    var swatches: [Color] = []
    let identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 30
    @ScaledMetric(relativeTo: .footnote) private var swatchSize: CGFloat = 14

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                    HStack(spacing: NookSpacing.small) {
                        icon
                        labelText
                    }
                    valueBlock(alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: NookSpacing.medium) {
                    icon
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    labelText
                        .layoutPriority(1)
                    valueBlock(alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, NookSpacing.small)
        .padding(.vertical, NookSpacing.small)
        .frame(minHeight: NookSpacing.minimumTapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text([value, detail].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityIdentifier("garment.fact.\(identifier)")
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize * 0.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.nook.accent)
            .frame(width: iconSize, height: iconSize)
            .background(Color.nook.tintStrong, in: Circle())
    }

    private var labelText: some View {
        Text(label)
            .nookTextStyle(.label)
            .fontWeight(.semibold)
            .foregroundStyle(.nook.textSecondary)
    }

    private func valueBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: NookSpacing.xxSmall) {
            HStack(spacing: 6) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in
                    Circle()
                        .fill(swatch)
                        .overlay(Circle().strokeBorder(Color.nook.textPrimary.opacity(0.25), lineWidth: 1))
                        .frame(width: swatchSize, height: swatchSize)
                }
                Text(value)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
                    .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail {
                Text(detail)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
