import DesignSystem
import Models
import SwiftUI

/// A suitcase's drawing at a given height, keeping the drawings' 104 x 182 shape. Decorative:
/// the row or button it's on carries the words.
struct SuitcaseArtView: View {
    let icon: SuitcaseIcon
    let height: CGFloat

    static let aspect: CGFloat = 104 / 182

    var body: some View {
        RoomArtImage(icon.art)
            .frame(width: height * Self.aspect, height: height)
            .accessibilityHidden(true)
    }
}

/// The name and picture of a suitcase: "+ Add a suitcase" (LR-17) and Edit on a suitcase. One
/// field, the five pictures, and one button. The name follows `NameRules.suitcaseName`: one
/// line, 1 to 40 characters, and not the same as another suitcase's.
struct SuitcaseEditor: View {
    enum Purpose {
        /// "+ Add a suitcase": the button says Add and pack.
        case add
        /// Edit: the button says Save.
        case edit
    }

    let purpose: Purpose
    /// Why a name can't be used, or `nil`.
    let problem: (String) -> NameProblem?
    /// Saves. Returns false when the store refused, so the sheet stays open.
    let save: (String, SuitcaseIcon) async -> Bool

    @State private var name: String
    @State private var icon: SuitcaseIcon
    @State private var isSaving = false
    @State private var didFail = false
    /// The name's problem shows once she has typed, or tried to save.
    @State private var showsProblem = false
    @AccessibilityFocusState private var focus: Field?

    private enum Field: Hashable {
        case name
    }

    init(
        purpose: Purpose, name: String = "", icon: SuitcaseIcon = .rolling, problem: @escaping (String) -> NameProblem?,
        save: @escaping (String, SuitcaseIcon) async -> Bool
    ) {
        self.purpose = purpose
        self.problem = problem
        self.save = save
        _name = State(initialValue: name)
        _icon = State(initialValue: icon)
        _showsProblem = State(initialValue: purpose == .edit)
    }

    var body: some View {
        let problem = problem(name)
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            EditorTextField(
                label: String(localized: "Name", bundle: .module, comment: "Label of a suitcase's name field"),
                prompt: String(
                    localized: "For example, Beach week", bundle: .module,
                    comment: "Prompt in a new suitcase's name field"),
                text: $name,
                problem: showsProblem
                    ? problem.map(SuitcasesText.nameLine(for:)) : (didFail ? SuitcasesText.failed : nil),
                identifier: "suitcaseEditor.name", focus: $focus, focusValue: .name)
            pictures
            NookButton(
                purpose == .add
                    ? String(
                        localized: "Add and pack", bundle: .module, comment: "Button: makes the suitcase, then packs it"
                    )
                    : String(localized: "Save", bundle: .module, comment: "Button: saves the new name"),
                systemImage: purpose == .add ? "plus" : "checkmark", isLoading: isSaving, fillsWidth: true
            ) {
                guard problem == nil else {
                    showsProblem = true
                    focus = .name
                    return
                }
                Task {
                    isSaving = true
                    didFail = !(await save(name, icon))
                    isSaving = false
                }
            }
            .accessibilityIdentifier("suitcaseEditor.save")
            if purpose == .add {
                Text(
                    "Pieces stay in your closet too. A suitcase only lists them, nothing is copied.", bundle: .module,
                    comment: "Under Add and pack"
                )
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: name) {
            didFail = false
            showsProblem = true
        }
    }

    /// The five drawings to choose from, in a wrapping row.
    private var pictures: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Text("Picture", bundle: .module, comment: "Label over the suitcase pictures")
                .nookTextStyle(.label)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            NookFlowLayout(spacing: NookSpacing.small, lineSpacing: NookSpacing.small) {
                ForEach(SuitcaseIcon.allCases, id: \.self) { choice in
                    pictureChoice(choice)
                }
            }
        }
    }

    private func pictureChoice(_ choice: SuitcaseIcon) -> some View {
        let isSelected = icon == choice
        return Button {
            icon = choice
        } label: {
            SuitcaseArtView(icon: choice, height: 70)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        NookRadius.shape(NookRadius.group)
                            .fill(Color.nook.tintStrong)
                            .softShadow(.drop, in: NookRadius.shape(NookRadius.group))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.nook.onAccent)
                            .frame(width: 22, height: 22)
                            .background(Color.nook.accent, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
                .contentShape(NookRadius.shape(NookRadius.group))
        }
        .buttonStyle(ClosetPressStyle())
        .accessibilityLabel(Text(SuitcasesText.iconName(choice)))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("suitcaseEditor.icon.\(choice.rawValue)")
    }
}
