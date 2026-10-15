import DesignSystem
import Models
import SwiftUI

/// "Add to a suitcase" on garment detail (Phase 13, `garment.html`'s suitcase sheet): every
/// suitcase that isn't archived, each with a tick that packs the piece or takes it out at once.
/// The piece stays in her closet; a suitcase only lists it, so nothing is copied (PRD §7.7).
/// With no suitcases yet, it offers Suitcases, where she can add one.
struct AddToSuitcaseSheet: View {
    let model: GarmentDetailModel
    let toggle: (Suitcase) -> Void
    let openSuitcases: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            if model.activeSuitcases.isEmpty {
                NookEmptyState(
                    String(localized: "No suitcases yet", bundle: .module, comment: "Suitcases: empty title"),
                    message: String(
                        localized: "Add a suitcase in Suitcases, then pack this piece in it.", bundle: .module,
                        comment: "Add to a suitcase: she has none"),
                    systemImage: "suitcase"
                ) {
                    NookButton(
                        String(localized: "Open Suitcases", bundle: .module, comment: "Button: opens Suitcases"),
                        systemImage: "suitcase", fillsWidth: true, action: openSuitcases)
                }
            } else {
                VStack(spacing: NookSpacing.xSmall) {
                    ForEach(model.activeSuitcases) { suitcase in
                        row(suitcase)
                    }
                }
            }
        }
    }

    private func row(_ suitcase: Suitcase) -> some View {
        let isPacked = model.garment.map { suitcase.contains($0.id) } ?? false
        return Button {
            toggle(suitcase)
        } label: {
            HStack(spacing: NookSpacing.medium) {
                SuitcaseArtView(icon: suitcase.icon, height: 46)
                    .frame(width: 34)
                Text(suitcase.name)
                    .nookTextStyle(.headline)
                    .foregroundStyle(.nook.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                SelectionTick(isSelected: isPacked)
            }
            .padding(.vertical, NookSpacing.xSmall)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(ClosetPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(suitcase.name))
        .accessibilityValue(
            Text(
                isPacked
                    ? String(localized: "Packed", bundle: .module, comment: "Add to a suitcase: the piece is in it")
                    : String(localized: "Not packed", bundle: .module, comment: "Suitcase filter choice"))
        )
        .accessibilityAddTraits(isPacked ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("addToSuitcase.\(suitcase.id.rawValue)")
    }
}
