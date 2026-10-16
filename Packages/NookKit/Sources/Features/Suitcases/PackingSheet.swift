import DesignSystem
import Models
import SwiftUI

/// "Pack Weekend" (`suitcase.html?add=1`, PRD §7.7 Adding existing clothes): her whole closet
/// with Closet's search and filters, and a tick on each piece. Ticking packs it, ticking again
/// takes it out, at once, so there's nothing to confirm and nothing is lost if she closes the
/// sheet. A piece can be in several suitcases; it's the same piece, nothing is copied. The
/// count at the top says how many are packed.
struct PackingSheet: View {
    let model: SuitcaseDetailModel
    @Bindable var list: ClosetModel
    /// Packs or unpacks a piece. The screen saves it and shows a toast if it couldn't.
    let toggle: (Garment.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(packedText)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
                Spacer(minLength: NookSpacing.small)
                Text(
                    "From your closet of \(model.closetGarments.count)", bundle: .module,
                    comment: "Packing sheet: how many pieces she can pack from"
                )
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("packing.count")
            Text(
                "Tick what goes in. A piece can be in more than one suitcase. It’s the same piece, so nothing is copied.",
                bundle: .module, comment: "Packing sheet: how it works"
            )
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            if list.isEmpty {
                NookEmptyState(
                    String(localized: "Your closet is empty", bundle: .module, comment: "Empty closet title"),
                    message: String(
                        localized: "Add pieces to your closet first, then pack them here.", bundle: .module,
                        comment: "Packing sheet: nothing in the closet"),
                    systemImage: "hanger")
            } else {
                NookSearchField(
                    String(localized: "Search your closet", bundle: .module, comment: "Closet search field prompt"),
                    text: $list.searchText, onSubmit: list.applySearchNow)
                ClosetFilters(model: list)
                    .padding(.horizontal, NookSpacing.screenMargin - NookSpacing.xLarge)
                if list.hasNoMatches {
                    NookEmptyState(
                        String(
                            localized: "No pieces match", bundle: .module,
                            comment: "Closet: nothing matches the filters"),
                        message: list.filterSummary,
                        systemImage: "magnifyingglass"
                    ) {
                        NookButton(
                            String(
                                localized: "Clear filters", bundle: .module,
                                comment: "Button: clears every filter and the search"),
                            systemImage: "xmark", kind: .soft, fillsWidth: true
                        ) {
                            list.clearFilters()
                        }
                    }
                } else {
                    GarmentGrid(
                        items: list.shown, now: list.loadedAt,
                        hint: String(
                            localized: "Packs it, or takes it out.", bundle: .module,
                            comment: "Hint on a piece in the packing sheet"),
                        identifierPrefix: "packing.garment",
                        selection: Set(list.shown.map(\.id).filter(model.isPacked))
                    ) { item in
                        toggle(item.id)
                    }
                    .padding(.top, NookSpacing.xSmall)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var packedText: String {
        let count = model.pieceCount
        return count == 0
            ? String(localized: "Nothing packed yet", bundle: .module, comment: "Packing sheet: nothing packed")
            : String(
                localized: "\(count) packed", bundle: .module,
                comment: "Packing sheet: how many pieces are packed, as in 5 packed")
    }
}
