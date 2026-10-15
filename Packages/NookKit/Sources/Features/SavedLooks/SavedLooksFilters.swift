import DesignSystem
import Models
import SwiftUI

/// Saved Looks' filter rows under the search field (LR-09), the same chips as Closet's: piece
/// chips, then colour swatches with their names. Clear sits on the count line under them, so it
/// never scrolls out of sight. Each row is a VoiceOver group named for what it filters; chips say
/// "Selected" when on.
///
/// At the accessibility text sizes the rows fold away behind Show filters, as on Closet, so the
/// looks come first.
struct SavedLooksFilters: View {
    let model: SavedLooksModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded = false

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                NookButton(
                    isExpanded
                        ? String(localized: "Hide filters", bundle: .module, comment: "Button at large text sizes")
                        : String(localized: "Show filters", bundle: .module, comment: "Button at large text sizes"),
                    systemImage: "line.3.horizontal.decrease", kind: .pill, size: .small
                ) {
                    isExpanded.toggle()
                }
                .accessibilityValue(
                    activeChoices > 0
                        ? Text(
                            "\(activeChoices) on", bundle: .module,
                            comment: "How many filters are on, spoken on Show filters") : Text("")
                )
                .accessibilityIdentifier("savedLooks.filter.toggle")
                .padding(.horizontal, NookSpacing.screenMargin)
                if isExpanded {
                    rows
                }
            }
        } else {
            rows
        }
    }

    private var activeChoices: Int {
        model.filter.categories.count + model.filter.colors.count
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            NookChipBar(String(localized: "Kind of piece", bundle: .module, comment: "Name of the piece chips row")) {
                ForEach(model.pieceKinds, id: \.self) { kind in
                    NookChip(kind.chipTitle, isSelected: model.filter.categories.contains(kind)) {
                        model.toggle(kind)
                    }
                    .accessibilityIdentifier("savedLooks.filter.kind.\(kind.rawValue)")
                }
            }
            if !model.colorChoices.isEmpty {
                NookChipBar(String(localized: "Colour", bundle: .module, comment: "Name of the colour swatches row")) {
                    ForEach(model.colorChoices, id: \.self) { color in
                        NookChip(
                            color.title, swatch: GarmentColor.swatch(for: color).color(in: colorScheme),
                            isSelected: model.filter.colors.contains(color)
                        ) {
                            model.toggle(color)
                        }
                        .accessibilityIdentifier("savedLooks.filter.color.\(color.rawValue)")
                    }
                }
            }
        }
    }
}
