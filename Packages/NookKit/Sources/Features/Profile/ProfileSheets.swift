import DesignSystem
import Models
import SwiftUI

/// Name on your sign (RD-03): one field, a small sign that shows what she types as she types it,
/// and Save. Names follow `NameRules.signName`: trimmed, one line, at most 20 characters, and
/// empty is allowed (the sign then says "Hello", RD-03.2).
struct NameSignSheet: View {
    let problem: (String) -> NameProblem?
    /// Saves the name. Returns false when it wasn't saved, so the sheet stays open.
    let save: (String) async -> Bool

    @State private var text: String
    @State private var isSaving = false
    @State private var didFail = false
    @AccessibilityFocusState private var focus: NameFocus?

    private enum NameFocus: Hashable {
        case name
    }

    init(name: String, problem: @escaping (String) -> NameProblem?, save: @escaping (String) async -> Bool) {
        self.problem = problem
        self.save = save
        _text = State(initialValue: name)
    }

    var body: some View {
        let problem = problem(text)
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            preview
            EditorTextField(
                label: ProfileText.nameField, prompt: ProfileText.namePrompt, text: $text,
                problem: problem.map(ProfileText.nameProblem) ?? (didFail ? ProfileText.failed : nil),
                identifier: "profile.nameField", focus: $focus, focusValue: .name)
            Text(ProfileText.nameEmptyNote)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NookButton(ProfileText.save, systemImage: "checkmark", isLoading: isSaving, fillsWidth: true) {
                Task {
                    isSaving = true
                    didFail = !(await save(text))
                    isSaving = false
                }
            }
            .disabled(problem != nil)
            .accessibilityIdentifier("profile.nameSave")
        }
        .onChange(of: text) { didFail = false }
    }

    /// The sign as it will look, so she sees a long name shrink or an empty one say "Hello".
    /// VoiceOver skips it: the field already reads what she typed.
    private var preview: some View {
        VStack(spacing: NookSpacing.xSmall) {
            ZStack(alignment: .topLeading) {
                RoomArtImage(.nameSign)
                NameSignText(stored: problem(text) == nil ? text : String(text.prefix(NameRules.signNameMaximum)))
                    .frame(width: ProfileHeader.signName.width, height: ProfileHeader.signName.height)
                    .offset(x: ProfileHeader.signName.minX, y: ProfileHeader.signName.minY)
            }
            .frame(width: ProfileHeader.signSize.width, height: ProfileHeader.signSize.height)
            Text(ProfileText.signPreview)
                .nookTextStyle(.caption)
                .foregroundStyle(.nook.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// One choice in a small Profile sheet.
struct ProfileChoice<Value: Hashable & Sendable> {
    let value: Value
    let title: String
    let detail: String
    let systemImage: String
    let identifier: String
}

/// Preferences and Avoid repeating outfits for (LR-03, LR-10): one row per value, the current one
/// ticked, and a note. Tapping a row saves it; the screen then closes the sheet.
struct ProfileChoices<Value: Hashable & Sendable>: View {
    let options: [ProfileChoice<Value>]
    let selected: Value
    let note: String
    /// Saves the choice. Returns false when it wasn't saved.
    let choose: (Value) async -> Bool

    @State private var didFail = false

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            ForEach(options, id: \.value) { option in
                StyleMeChoiceRow(
                    title: option.title, subtitle: option.detail, systemImage: option.systemImage,
                    isSelected: option.value == selected, identifier: option.identifier
                ) {
                    Task { didFail = !(await choose(option.value)) }
                }
            }
            if didFail {
                FieldProblemNote(message: ProfileText.failed)
            }
            Text(note)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
