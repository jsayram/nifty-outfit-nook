import DesignSystem
import Models
import SwiftUI

/// Remember this name (PRD §7.6), on the detail of a piece she opened from Closet's Possible
/// matches: her search words in a field she can change, kept as another name for this piece
/// only when she taps Remember. Nothing is kept otherwise, and the search itself never is.
struct RememberNameCard: View {
    let pieceName: String
    @Binding var text: String
    var problem: FieldProblem?
    var isSaving = false
    let remember: () -> Void
    let decline: () -> Void

    @AccessibilityFocusState private var focus: Bool?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Label {
                Text("Remember this name?", bundle: .module, comment: "Heading of the Remember this name card")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "text.badge.plus")
                    .accessibilityHidden(true)
            }
            .nookTextStyle(.title)
            .foregroundStyle(.nook.textPrimary)
            .accessibilityAddTraits(.isHeader)
            Text(
                "Keep these words as another name for \(pieceName), so the same search finds it next time.",
                bundle: .module, comment: "Remember this name card, with the piece's name"
            )
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            EditorTextField(
                label: String(
                    localized: "Other name", bundle: .module, comment: "Field on the Remember this name card"),
                prompt: String(
                    localized: "Words to remember", bundle: .module,
                    comment: "Prompt in the Remember this name field when it's empty"),
                text: $text,
                problem: problem.map { GarmentEditorText.problem($0, in: .otherNames) },
                identifier: "rememberName",
                focus: $focus,
                focusValue: true
            )
            Text(
                "Only these words are kept, on this piece. Your search isn’t saved.", bundle: .module,
                comment: "Remember this name card: what Remember keeps"
            )
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            buttons
                .padding(.top, NookSpacing.xSmall)
        }
        .padding(NookSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nook.tint, in: NookRadius.shape(NookRadius.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("garment.remember")
        .onChange(of: problem) { _, newValue in
            if newValue != nil { focus = true }
        }
    }

    @ViewBuilder private var buttons: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: NookSpacing.small))
            : AnyLayout(HStackLayout(spacing: NookSpacing.small))
        layout {
            NookButton(
                String(localized: "Remember", bundle: .module, comment: "Button on the Remember this name card"),
                systemImage: "checkmark", isLoading: isSaving, fillsWidth: true, action: remember
            )
            .accessibilityHint(
                Text(
                    "Adds these words to \(pieceName)’s other names.", bundle: .module,
                    comment: "Hint on Remember, with the piece's name")
            )
            .accessibilityIdentifier("garment.remember.save")
            NookButton(
                String(
                    localized: "Not now", bundle: .module,
                    comment:
                        "Button: closes a question without doing anything, as on the laundry tracking sheet and Remember this name"
                ),
                kind: .soft, fillsWidth: true, action: decline
            )
            .accessibilityHint(
                Text("Nothing is kept.", bundle: .module, comment: "Hint on Not now on the Remember this name card")
            )
            .accessibilityIdentifier("garment.remember.decline")
        }
    }
}
