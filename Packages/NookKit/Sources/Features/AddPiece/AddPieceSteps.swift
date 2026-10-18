import DesignSystem
import Models
import SwiftUI

/// "How would you like to add it?" (`garment-edit.html`): Take photo, Choose from Photos, Paste
/// and Describe in words. The photo choices go through the stand-in until Phase 22a, which the
/// line under them says, and its loading and "couldn't be read" states.
struct AddPieceChoices: View {
    let model: GarmentEditorModel
    let actions: GarmentEditorActions

    var body: some View {
        switch model.photoState {
        case .loading:
            NookLoadingState(
                String(localized: "Getting your photo", bundle: .module, comment: "Add a piece: the photo step is busy")
            )
            .padding(.top, NookSpacing.xLarge)
        case .failed:
            NookErrorState(
                String(
                    localized: "That photo couldn’t be read", bundle: .module,
                    comment: "Add a piece: the photo stand-in failed"),
                message: String(
                    localized: "Nothing was saved. You can try another photo, or describe the piece in words instead.",
                    bundle: .module, comment: "Add a piece: after a photo couldn't be read"),
                retryTitle: String(
                    localized: "Try another photo", bundle: .module, comment: "Button: back to the photo choices"),
                retry: actions.tryAnotherPhoto
            ) {
                NookButton(
                    String(localized: "Describe in words", bundle: .module, comment: "Button: adds a piece by words"),
                    systemImage: "pencil", kind: .soft, fillsWidth: true, action: actions.describeInWords
                )
                .accessibilityIdentifier("addPiece.error.describe")
            }
            .padding(.top, NookSpacing.large)
        case .idle:
            choices
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            photoChoices
                .tourAnchor(
                    AddPieceTour.Anchor.photo,
                    label: String(
                        localized: "Take photo, Choose from Photos or Paste", bundle: .module,
                        comment: "VoiceOver name of Add a piece's three photo choices, in its tour"))
            Button(action: actions.describeInWords) {
                NookRow(
                    String(localized: "Describe in words", bundle: .module, comment: "Add a piece choice"),
                    subtitle: String(
                        localized: "No photo needed. You can add one later.", bundle: .module,
                        comment: "Add a piece choice: under Describe in words"),
                    systemImage: "pencil", accessory: .chevron)
            }
            .buttonStyle(.nookRow)
            .accessibilityIdentifier("addPiece.words")
            .tourAnchor(
                AddPieceTour.Anchor.words,
                label: String(localized: "Describe in words", bundle: .module, comment: "Add a piece choice"),
                action: actions.describeInWords)
            Label {
                Text(
                    "Photos aren’t built yet. For now each photo choice adds the same example photo, and nothing asks for your camera or photos.",
                    bundle: .module, comment: "Add a piece: under the choices, while photos are a stand-in"
                )
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
            }
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .padding(.horizontal, NookSpacing.small)
            .padding(.top, NookSpacing.small)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("addPiece.standInNote")
        }
    }

    /// Take photo, Choose from Photos and Paste, which the tour points at together.
    private var photoChoices: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            choice(
                .camera, title: String(localized: "Take photo", bundle: .module, comment: "Add a piece choice"),
                subtitle: String(
                    localized: "One piece, flat or on a hanger", bundle: .module,
                    comment: "Add a piece choice: under Take photo"),
                systemImage: "camera")
            choice(
                .library,
                title: String(localized: "Choose from Photos", bundle: .module, comment: "Add a piece choice"),
                subtitle: String(
                    localized: "Only the picture you pick is shared with the app", bundle: .module,
                    comment: "Add a piece choice: under Choose from Photos"),
                systemImage: "photo")
            choice(
                .paste, title: String(localized: "Paste", bundle: .module, comment: "Add a piece choice"),
                subtitle: String(
                    localized: "A photo you copied from somewhere else", bundle: .module,
                    comment: "Add a piece choice: under Paste"),
                systemImage: "doc.on.clipboard")
        }
    }

    private func choice(_ source: PhotoSource, title: String, subtitle: String, systemImage: String) -> some View {
        Button {
            actions.choosePhoto(source)
        } label: {
            NookRow(title, subtitle: subtitle, systemImage: systemImage, accessory: .chevron)
        }
        .buttonStyle(.nookRow)
        .accessibilityIdentifier("addPiece.\(source.rawValue)")
    }
}

/// "Describe it" (`garment-edit.html?mode=text`): her words, Suggest details, then each
/// suggestion to accept or skip. Nothing is filled in until she accepts it, and the line under
/// the list says the words never leave the device.
struct DescribeInWords: View {
    @Bindable var model: GarmentEditorModel
    let actions: GarmentEditorActions
    let focus: AccessibilityFocusState<GarmentField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            Label {
                VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                    Text("No photo yet", bundle: .module, comment: "Describe in words: the piece has no photo")
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                    Text(
                        "A plain drawing stands in until you add one.", bundle: .module,
                        comment: "Describe in words: under No photo yet"
                    )
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "photo")
                    .foregroundStyle(.nook.accent)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            EditorTextField(
                label: String(
                    localized: "In your own words", bundle: .module, comment: "Describe in words: field label"),
                prompt: String(
                    localized: "Like “Sage green cardigan with gold buttons, soft and cozy”", bundle: .module,
                    comment: "Describe in words: field prompt"),
                text: $model.description, isMultiline: true, problem: descriptionProblem, identifier: "description",
                focus: focus, focusValue: .notes)
            NookButton(
                String(localized: "Suggest details", bundle: .module, comment: "Button: reads her words for details"),
                systemImage: "sparkles", kind: .soft, isLoading: model.suggestionState == .loading, fillsWidth: true,
                action: actions.suggest
            )
            .accessibilityIdentifier("words.suggest")
            suggestions
            NookButton(
                String(localized: "Continue", bundle: .module, comment: "Button: to the details form"),
                systemImage: "chevron.right", fillsWidth: true, action: actions.continueFromWords
            )
            .accessibilityIdentifier("words.continue")
        }
    }

    private var descriptionProblem: String? {
        switch model.descriptionProblem {
        case .none: nil
        case .empty:
            String(
                localized: "Type a few words about the piece first.", bundle: .module,
                comment: "Describe in words: Suggest details with nothing typed")
        case .some(let problem): GarmentEditorText.problem(problem, in: .notes)
        }
    }

    @ViewBuilder private var suggestions: some View {
        switch model.suggestionState {
        case .idle, .loading:
            EmptyView()
        case .failed:
            note(
                String(
                    localized: "Suggestions didn’t load. You can fill in the details yourself.", bundle: .module,
                    comment: "Describe in words: the reader failed"))
        case .loaded:
            if model.suggestions.isEmpty {
                note(
                    String(
                        localized: "No details found in those words. You can fill them in on the next step.",
                        bundle: .module, comment: "Describe in words: nothing recognised"))
            } else {
                VStack(alignment: .leading, spacing: NookSpacing.small) {
                    Text("Suggested, check each one", bundle: .module, comment: "Describe in words: list heading")
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(model.suggestions) { row in
                        SuggestionRowView(row: row) { decision in
                            model.decide(decision, for: row.id)
                        }
                    }
                    Text(
                        "Made on this device from your words. Nothing is sent, and nothing is filled in until you accept it.",
                        bundle: .module, comment: "Describe in words: under the suggestions"
                    )
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NookSpacing.small)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nookCard(padding: NookSpacing.medium)
            .accessibilityIdentifier("words.note")
    }
}

/// One suggestion: what it fills and the value, with Accept and Skip. At the accessibility
/// sizes the buttons go under the words.
private struct SuggestionRowView: View {
    let row: GarmentEditorModel.SuggestionRow
    let decide: (GarmentEditorModel.SuggestionRow.Decision) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let label = GarmentEditorText.suggestionLabel(row.suggestion)
        let value = GarmentEditorText.suggestionValue(row.suggestion)
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.small))
            : AnyLayout(HStackLayout(spacing: NookSpacing.small))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                Text(value)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
                    .strikethrough(row.decision == .skipped)
                    .opacity(row.decision == .skipped ? 0.6 : 1)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            HStack(spacing: NookSpacing.small) {
                NookChip(
                    row.decision == .accepted
                        ? String(localized: "Added", bundle: .module, comment: "Suggestion chip once accepted")
                        : String(localized: "Accept", bundle: .module, comment: "Suggestion chip"),
                    systemImage: "checkmark", isSelected: row.decision == .accepted
                ) {
                    decide(.accepted)
                }
                .accessibilityLabel(
                    Text(
                        "Accept \(label): \(value)", bundle: .module,
                        comment: "VoiceOver: accept a suggestion, with its field and value")
                )
                .accessibilityIdentifier("words.suggestion.\(row.id).accept")
                NookChip(
                    row.decision == .skipped
                        ? String(localized: "Skipped", bundle: .module, comment: "Suggestion chip once skipped")
                        : String(localized: "Skip", bundle: .module, comment: "Suggestion chip"),
                    isSelected: row.decision == .skipped
                ) {
                    decide(.skipped)
                }
                .accessibilityLabel(
                    Text("Skip \(label)", bundle: .module, comment: "VoiceOver: skip a suggestion, with its field")
                )
                .accessibilityIdentifier("words.suggestion.\(row.id).skip")
            }
        }
        .padding(.leading, NookSpacing.medium)
        .padding(.trailing, NookSpacing.small)
        .padding(.vertical, NookSpacing.xSmall)
        .background(Color.nook.tint, in: NookRadius.shape(NookRadius.group))
    }
}
