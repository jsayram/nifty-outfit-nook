import DesignSystem
import Models
import SwiftUI

/// The text list of a look's pieces that sits under its bundle (RD-07), so the look reads
/// without the picture and VoiceOver can reach each piece on its own (RD-07.3).
///
/// One row per piece, in body order, on a soft tint with no lines between rows (`.pcs` in
/// `results-versions.html`). A piece she doesn't own says "Not in your closet" and, when
/// `onFindOne` is given, has a Find one button (LR-05b). With `showsSameAsSimple`, pieces shared
/// with the Simple version say "Same as Simple" (LR-05a.3).
struct LookPieceList: View {
    let content: LookBundleContent
    var showsSameAsSimple = false
    var onFindOne: ((LookBundlePiece) -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(content.pieces) { piece in
                row(piece)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nookCard(.tint, padding: 0)
    }

    @ViewBuilder
    private func row(_ piece: LookBundlePiece) -> some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.xSmall))
            : AnyLayout(HStackLayout(spacing: NookSpacing.small))
        layout {
            // An idea's tag goes under its name, so the name and Find one keep their room.
            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                Text(piece.name)
                    .nookTextStyle(.body)
                    .foregroundStyle(.nook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(spokenRow(piece)))
                if piece.isIdea {
                    NookBadge(LookBundleText.notInYourCloset, systemImage: "tag", tone: .accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !piece.isIdea, let mark = markTitle(for: piece) {
                NookBadge(mark, tone: .neutral)
                    .accessibilityHidden(true)
            }
            if piece.isIdea, let onFindOne {
                NookButton(
                    String(localized: "Find one", bundle: .module, comment: "Button on a look's piece she doesn't own"),
                    systemImage: "magnifyingglass", kind: .pill, size: .small
                ) { onFindOne(piece) }
                // Keeps the icon beside the words while there's room (see the playbook, Phase 7b).
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                .accessibilityLabel(
                    Text(
                        "Find one like \(piece.name)", bundle: .module,
                        comment: "Spoken label of Find one, with the piece's name")
                )
                .accessibilityIdentifier("lookPieces.findOne.\(piece.id)")
            }
        }
        .padding(.horizontal, NookSpacing.large)
        .padding(.vertical, NookSpacing.small)
        .frame(minHeight: NookSpacing.minimumTapTarget)
    }

    private func markTitle(for piece: LookBundlePiece) -> String? {
        if piece.isIdea { return LookBundleText.notInYourCloset }
        if showsSameAsSimple && piece.isSameAsSimple {
            return String(
                localized: "Same as Simple", bundle: .module, comment: "Mark on a piece also in the Simple version")
        }
        return nil
    }

    /// The row as VoiceOver reads it: the name, then its mark.
    private func spokenRow(_ piece: LookBundlePiece) -> String {
        guard let mark = markTitle(for: piece) else { return piece.name }
        return String(
            localized: "\(piece.name), \(mark)", bundle: .module,
            comment: "Spoken row in a look's piece list: the piece's name, then a mark such as Same as Simple")
    }
}
