import DesignSystem
import Models
import SwiftUI

/// The filter rows under the search field (LR-09, LR-11, RD-11): piece chips, colour swatches,
/// then the Suitcase menu, the Dirty chip while laundry tracking is on, and Clear while anything
/// is set. Each row is a VoiceOver group named for what it filters; chips say "Selected" when on.
///
/// At the accessibility text sizes the rows wrap instead of scrolling, so no chip is hidden. That
/// makes them several screens tall at AX5, so there they fold away behind a Show filters button
/// and her pieces come first.
struct ClosetFilters: View {
    let model: ClosetModel

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
                .accessibilityIdentifier("closet.filter.toggle")
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
        let filter = model.filter
        return filter.categories.count + filter.colors.count + (filter.packing == .any ? 0 : 1)
            + (filter.laundry == nil ? 0 : 1)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            if !model.pieceKinds.isEmpty {
                NookChipBar(
                    String(localized: "Kind of piece", bundle: .module, comment: "Name of the piece chips row")
                ) {
                    ForEach(model.pieceKinds, id: \.self) { kind in
                        NookChip(kind.chipTitle, isSelected: model.filter.categories.contains(kind)) {
                            model.toggle(kind)
                        }
                        .accessibilityIdentifier("closet.filter.kind.\(kind.rawValue)")
                    }
                }
            }
            if !model.colorChoices.isEmpty {
                NookChipBar(String(localized: "Colour", bundle: .module, comment: "Name of the colour swatches row")) {
                    ForEach(model.colorChoices, id: \.self) { color in
                        NookChip(
                            color.title, swatch: swatch(color), isSelected: model.filter.colors.contains(color)
                        ) {
                            model.toggle(color)
                        }
                        .accessibilityIdentifier("closet.filter.color.\(color.rawValue)")
                    }
                }
            }
            NookChipBar(
                String(localized: "Suitcase and laundry", bundle: .module, comment: "Name of the third filter row")
            ) {
                suitcaseMenu
                if model.showsLaundryFilter {
                    NookChip(
                        String(
                            localized: "Dirty (\(model.dirtyCount))", bundle: .module,
                            comment: "Laundry filter chip with how many pieces are in the wash"),
                        systemImage: "basket", isSelected: model.filter.laundry == .dirty
                    ) {
                        model.toggleDirty()
                    }
                    .accessibilityIdentifier("closet.filter.dirty")
                }
                if model.filter.isActive {
                    Button {
                        model.clearFilters()
                    } label: {
                        Text("Clear", bundle: .module, comment: "Clears every filter and the search")
                    }
                    .buttonStyle(.nook(.text, size: .small))
                    .accessibilityLabel(
                        Text("Clear filters", bundle: .module, comment: "Spoken name of the Clear button")
                    )
                    .accessibilityIdentifier("closet.filter.clear")
                }
            }
        }
    }

    /// The Suitcase filter (LR-11): In a suitcase, Not packed, then each suitcase by name.
    private var suitcaseMenu: some View {
        let title = String(localized: "Suitcase", bundle: .module, comment: "Suitcase filter chip")
        return NookMenuChip(
            model.packingTitle ?? title, systemImage: "suitcase", isSelected: model.filter.packing != .any
        ) {
            Picker(selection: Binding(get: { model.filter.packing }, set: { model.setPacking($0) })) {
                Text("Any", bundle: .module, comment: "Suitcase filter choice: no filter")
                    .tag(GarmentFilter.Packing.any)
                Text("In a suitcase", bundle: .module, comment: "Suitcase filter choice")
                    .tag(GarmentFilter.Packing.inASuitcase)
                Text("Not packed", bundle: .module, comment: "Suitcase filter choice")
                    .tag(GarmentFilter.Packing.notPacked)
                if !model.suitcases.isEmpty {
                    Section {
                        ForEach(model.suitcases) { suitcase in
                            Text(suitcase.name).tag(GarmentFilter.Packing.suitcase(suitcase.id))
                        }
                    }
                }
            } label: {
                Text(title)
            }
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(
            Text(
                model.packingTitle
                    ?? String(localized: "Any", bundle: .module, comment: "Suitcase filter choice: no filter"))
        )
        .accessibilityIdentifier("closet.filter.suitcase")
    }

    private func swatch(_ color: ColorName) -> Color {
        if color == .multicolor {
            // One dot can't show many colours; the stripes' first colour stands in, and the
            // name says the rest.
            return GarmentColor.multicolorStripes[0].color(in: colorScheme)
        }
        return GarmentColor.fill(for: color).color(in: colorScheme)
    }
}
