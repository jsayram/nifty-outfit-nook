import DesignSystem
import Models
import SwiftUI

/// A list of her pieces to choose one from, with Closet's search, filters and grid (Phase 11).
/// See all in Swap a piece and Add a piece in Make your own look both open it in a sheet.
///
/// The model is a `ClosetModel` with a `PieceScope`, filled from data the opening screen
/// already has, so opening it reads nothing and sends nothing.
struct PiecePicker: View {
    @Bindable var model: ClosetModel
    /// A line above the search, such as "From Main closet. Only the top changes."
    var lead: String?
    /// The search field's prompt.
    let prompt: String
    /// What choosing a piece does, for VoiceOver.
    let hint: String
    /// Shown when the scope holds nothing at all.
    let emptyTitle: String
    let emptyMessage: String
    let choose: (Garment.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            if let lead {
                Text(lead)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.isEmpty {
                NookEmptyState(emptyTitle, message: emptyMessage, systemImage: "hanger")
                    .accessibilityIdentifier("picker.empty")
            } else {
                NookSearchField(prompt, text: $model.searchText, onSubmit: model.applySearchNow)
                ClosetFilters(model: model)
                    // The rows pad themselves by the screen margin; this lines their first chip up
                    // with the sheet's wider margin and lets them scroll a little past it.
                    .padding(.horizontal, NookSpacing.screenMargin - NookSpacing.xLarge)
                Text(model.countText)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .accessibilityIdentifier("picker.count")
                if model.hasNoMatches {
                    NookEmptyState(
                        String(
                            localized: "No pieces match", bundle: .module,
                            comment: "Closet: nothing matches the filters"
                        ),
                        message: model.filterSummary,
                        systemImage: "magnifyingglass"
                    ) {
                        NookButton(
                            String(
                                localized: "Clear filters", bundle: .module,
                                comment: "Button: clears every filter and the search"),
                            systemImage: "xmark", kind: .soft, fillsWidth: true
                        ) {
                            model.clearFilters()
                        }
                    }
                } else {
                    GarmentGrid(
                        items: model.shown, now: model.loadedAt, hint: hint, identifierPrefix: "picker.garment"
                    ) { item in
                        choose(item.id)
                    }
                    .padding(.top, NookSpacing.xSmall)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A picker's model is presented as a sheet item, one sheet per opening.
extension ClosetModel: Identifiable {}
