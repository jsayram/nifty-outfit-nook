import DesignSystem
import Models
import SwiftUI

/// "Add a piece that fits you well" (LR-13): the brand, the kind of piece, the size as printed
/// and how it fits. Brand, kind and size are needed; Save says what's missing. Nothing is chosen
/// for her: the kind starts empty, as on Add a piece, and the fit starts on Fits well, which is
/// what the row is for.
struct FitPieceSheet: View {
    /// Adds the piece. Returns false when it wasn't saved, so the sheet stays open.
    let add: (FitPiece) async -> Bool

    @State private var brand = ""
    @State private var category: GarmentCategory?
    @State private var size = ""
    @State private var result: FitResult = .fitsWell
    @State private var showsProblems = false
    @State private var didFail = false
    @State private var isSaving = false
    @AccessibilityFocusState private var focus: Field?

    enum Field: Hashable {
        case brand
        case kind
        case size
    }

    init(
        brand: String = "", category: GarmentCategory? = nil, size: String = "", showsProblems: Bool = false,
        add: @escaping (FitPiece) async -> Bool
    ) {
        self.add = add
        _brand = State(initialValue: brand)
        _category = State(initialValue: category)
        _size = State(initialValue: size)
        _showsProblems = State(initialValue: showsProblems)
    }

    var body: some View {
        let problems = showsProblems ? ProfileModel.problems(brand: brand, size: size) : nil
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            Text(FitText.addPieceLine)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            EditorTextField(
                label: FitText.brand, prompt: FitText.brandPrompt, text: $brand,
                problem: problems?.brand.map { problemText($0, missing: FitText.brandMissing) },
                identifier: "fitPiece.brand", focus: $focus, focusValue: .brand)
            EditorChoiceGroup(
                label: FitText.kind, problem: showsProblems && category == nil ? kindMissing : nil,
                identifier: "fitPiece.kind", focus: $focus, focusValue: .kind
            ) {
                ForEach(GarmentCategory.allCases, id: \.self) { kind in
                    NookChip(kind.singularTitle, isSelected: category == kind) { category = kind }
                        .accessibilityIdentifier("fitPiece.kind.\(kind.rawValue)")
                }
            }
            EditorTextField(
                label: FitText.size, prompt: FitText.sizePrompt, text: $size,
                problem: problems?.size.map { problemText($0, missing: FitText.sizeMissing) },
                identifier: "fitPiece.size", focus: $focus, focusValue: .size)
            EditorChoiceGroup(label: FitText.howItFits, identifier: "fitPiece.result", focus: $focus) {
                ForEach(FitResult.allCases, id: \.self) { choice in
                    NookChip(choice.title, isSelected: result == choice) { result = choice }
                }
            }
            if didFail {
                FieldProblemNote(message: ProfileText.failed)
            }
            NookButton(FitText.addPiece, systemImage: "plus", isLoading: isSaving, fillsWidth: true) {
                submit()
            }
            .accessibilityIdentifier("fitPiece.save")
        }
        .hiddenWhenInactive()
    }

    private var kindMissing: String {
        String(localized: "Pick the kind of piece.", bundle: .module, comment: "Fitting piece sheet: no kind chosen")
    }

    private func problemText(_ problem: NameProblem, missing: String) -> String {
        switch problem {
        case .empty: missing
        case .tooLong(let maximum): FitText.tooLong(maximum)
        case .controlCharacters, .duplicate: ProfileText.nameProblem(.controlCharacters)
        }
    }

    private func submit() {
        let problems = ProfileModel.problems(brand: brand, size: size)
        guard problems == nil, let category,
            let brand = try? MeasurementRules.fitBrand(brand), let size = try? MeasurementRules.fitSize(size)
        else {
            showsProblems = true
            focus = problems?.brand != nil ? .brand : category == nil ? .kind : .size
            return
        }
        let piece = FitPiece(id: .random(), brand: brand, category: category, sizeLabel: size, result: result)
        Task {
            isSaving = true
            didFail = !(await add(piece))
            isSaving = false
        }
    }
}
