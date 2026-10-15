import DesignSystem
import Models
import SwiftUI

/// The text list of a look's pieces that sits under its bundle (RD-07), so the look reads
/// without the picture and VoiceOver can reach each piece on its own (RD-07.3).
///
/// One row per piece, in body order, on a soft tint with no lines between rows (`.pcs` in
/// `results-versions.html`). A piece she doesn't own says "Not in your closet" and, when
/// `onFindOne` is given, has a Find one button (LR-05b). With `showsSameAsSimple`, pieces shared
/// with the Simple version say "Same as Simple", and `changes` marks the others "Swapped" or
/// "Added" (LR-05a.3), in words rather than colour. A piece that left her closet is in softer
/// text with why, and Swap it when `onSwapIt` is given (LR-16.4). With `onOpen`, each of her
/// pieces is a button that opens it (Phase 12a).
struct LookPieceList: View {
    let content: LookBundleContent
    var showsSameAsSimple = false
    /// How pieces differ from Simple, by piece ID (Phase 10b).
    var changes: [String: LookPieceChange] = [:]
    var onFindOne: ((LookBundlePiece) -> Void)?
    /// Opens a piece of hers (garment detail, Phase 12a). Each of her pieces becomes a button.
    var onOpen: ((LookBundlePiece) -> Void)?
    /// Swap it on a piece that left her closet (LR-16.4, Phase 12a).
    var onSwapIt: ((LookBundlePiece) -> Void)?

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
            if let onOpen, !piece.isIdea {
                Button {
                    onOpen(piece)
                } label: {
                    HStack(spacing: NookSpacing.small) {
                        label(piece)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.nook.chevron)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.nookRow)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(spokenRow(piece)))
                .accessibilityHint(
                    Text("Opens this piece.", bundle: .module, comment: "Hint on a piece in a saved look's list")
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("lookPieces.open.\(piece.id)")
            } else {
                label(piece)
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
            if piece.isRemoved, let onSwapIt {
                NookButton(
                    String(
                        localized: "Swap it", bundle: .module,
                        comment: "Button on a saved look's piece that left her closet (LR-16.4)"),
                    systemImage: "arrow.left.arrow.right", kind: .pill, size: .small
                ) { onSwapIt(piece) }
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                .accessibilityLabel(
                    Text(
                        "Swap \(piece.name) for one of your pieces", bundle: .module,
                        comment: "Spoken label of Swap it, with the piece's name")
                )
                .accessibilityIdentifier("lookPieces.swapIt.\(piece.id)")
            }
        }
        .padding(.horizontal, NookSpacing.large)
        .padding(.vertical, NookSpacing.small)
        .frame(minHeight: NookSpacing.minimumTapTarget)
    }

    /// The name, with the idea tag or the removal note under it, and a mark beside it.
    private func label(_ piece: LookBundlePiece) -> some View {
        // The same arrangement as the row, so the mark sits under the name at the large sizes.
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.xSmall))
            : AnyLayout(HStackLayout(spacing: NookSpacing.small))
        return layout {
            // An idea's tag goes under its name, so the name and Find one keep their room.
            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                Text(piece.name)
                    .nookTextStyle(.body)
                    .foregroundStyle(piece.isRemoved ? .nook.textSecondary : .nook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(spokenRow(piece)))
                if piece.isIdea {
                    NookBadge(LookBundleText.notInYourCloset, systemImage: "tag", tone: .accent)
                        .accessibilityHidden(true)
                }
                if let removal = piece.removal {
                    NookBadge(LookBundleText.removalNote(removal), tone: .neutral)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !piece.isIdea, !piece.isRemoved, let mark = markTitle(for: piece) {
                NookBadge(mark, tone: changes[piece.id] == nil ? .neutral : .accent)
                    .accessibilityHidden(true)
            }
        }
    }

    private func markTitle(for piece: LookBundlePiece) -> String? {
        if piece.isIdea { return LookBundleText.notInYourCloset }
        if let removal = piece.removal { return LookBundleText.removalNote(removal) }
        if let change = changes[piece.id] { return change.title }
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
