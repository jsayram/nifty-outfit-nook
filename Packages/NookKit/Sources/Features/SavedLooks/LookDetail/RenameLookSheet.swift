import DesignSystem
import Models
import SwiftUI

/// Rename look: one field with the name, its problem in words while there is one, and Save.
/// Names follow `NameRules.lookName`: trimmed, one line, 1 to 60 characters.
struct RenameLookSheet: View {
    let problem: (String) -> NameProblem?
    /// Saves the name. Returns false when the store refused it, so the sheet stays open.
    let save: (String) async -> Bool

    @State private var text: String
    @State private var isSaving = false
    @State private var didFail = false
    @AccessibilityFocusState private var focus: RenameFocus?

    init(draft: RenameDraft, problem: @escaping (String) -> NameProblem?, save: @escaping (String) async -> Bool) {
        self.problem = problem
        self.save = save
        _text = State(initialValue: draft.text)
    }

    private enum RenameFocus: Hashable {
        case name
    }

    var body: some View {
        let problem = problem(text)
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            EditorTextField(
                label: LookDetailText.nameLabel, prompt: LookDetailText.renameTitle, text: $text,
                problem: problem.map(LookDetailText.nameLine(for:)) ?? (didFail ? LookDetailText.failedToast : nil),
                identifier: "lookDetail.renameField", focus: $focus, focusValue: .name)
            NookButton(LookDetailText.save, systemImage: "checkmark", isLoading: isSaving, fillsWidth: true) {
                Task {
                    isSaving = true
                    didFail = !(await save(text))
                    isSaving = false
                }
            }
            .disabled(problem != nil)
            .accessibilityIdentifier("lookDetail.renameSave")
        }
        .onChange(of: text) { didFail = false }
    }
}
