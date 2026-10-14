import DesignSystem
import Models
import SwiftUI

/// The details form (`garment-edit.html?step=details`): the picture, then name, kind, colours
/// and the shade, fit, how dressy and how warm, seasons, occasions, brand, size and notes, and
/// Save. Only the name and kind are required; everything else has a sensible default or can be
/// left empty.
struct GarmentDetailsForm: View {
    @Bindable var model: GarmentEditorModel
    let actions: GarmentEditorActions
    let focus: AccessibilityFocusState<GarmentField?>.Binding

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            PhotoRow(model: model, addPhoto: actions.addPhoto)
            EditorTextField(
                label: GarmentEditorText.label(for: .name),
                prompt: String(
                    localized: "Like “Cute pink shirt”", bundle: .module, comment: "Add a piece: name field prompt"),
                text: $model.details.name, problem: problem(.name), identifier: "name", focus: focus,
                focusValue: .name
            )
            .id(GarmentField.name)
            kind
                .id(GarmentField.category)
            colours
            single(
                String(localized: "Fit", bundle: .module, comment: "Add a piece: field label, how it's cut"),
                identifier: "fit",
                choices: GarmentFit.allCases.map { Optional($0) } + [nil], selection: $model.details.fit
            ) { fit in
                fit?.title ?? String(localized: "Not sure", bundle: .module, comment: "Add a piece: fit unknown")
            }
            single(
                String(localized: "How dressy", bundle: .module, comment: "Add a piece: field label"),
                identifier: "dressiness", choices: Dressiness.allCases, selection: $model.details.dressiness,
                title: \.title)
            single(
                String(localized: "How warm", bundle: .module, comment: "Add a piece: field label"),
                identifier: "warmth", choices: Warmth.allCases, selection: $model.details.warmth, title: \.title)
            seasons
            occasions
            EditorTextField(
                label: GarmentEditorText.label(for: .brand), isOptional: true,
                prompt: String(localized: "Like “Old Navy”", bundle: .module, comment: "Add a piece: brand prompt"),
                text: $model.details.brand, problem: problem(.brand), identifier: "brand", focus: focus,
                focusValue: .brand
            )
            .id(GarmentField.brand)
            EditorTextField(
                label: GarmentEditorText.label(for: .sizeLabel), isOptional: true,
                prompt: String(localized: "Like “0 Petite”", bundle: .module, comment: "Add a piece: size prompt"),
                text: $model.details.sizeLabel, problem: problem(.sizeLabel), identifier: "sizeLabel", focus: focus,
                focusValue: .sizeLabel
            )
            .id(GarmentField.sizeLabel)
            EditorTextField(
                label: GarmentEditorText.label(for: .notes), isOptional: true,
                prompt: String(
                    localized: "Little things you notice, like “Bow at the neck”", bundle: .module,
                    comment: "Add a piece: notes prompt"),
                text: $model.details.notes, isMultiline: true, problem: problem(.notes), identifier: "notes",
                focus: focus, focusValue: .notes
            )
            .id(GarmentField.notes)
            save
        }
    }

    private func problem(_ field: GarmentField) -> String? {
        guard model.showsProblems, let problem = model.problems[field] else { return nil }
        return GarmentEditorText.problem(problem, in: field)
    }

    // MARK: Groups

    private var kind: some View {
        EditorChoiceGroup(
            label: GarmentEditorText.label(for: .category), problem: problem(.category), identifier: "category",
            focus: focus, focusValue: .category
        ) {
            ForEach(GarmentCategory.allCases, id: \.self) { category in
                NookChip(category.chipTitle, isSelected: model.details.category == category) {
                    model.details.category = category
                }
                .accessibilityIdentifier("kind.\(category.rawValue)")
            }
        }
    }

    private var colours: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            EditorChoiceGroup(
                label: String(localized: "Colour", bundle: .module, comment: "Add a piece: field label"),
                note: model.details.colors.count > 1
                    ? String(
                        localized: "The first one you picked is the main colour.", bundle: .module,
                        comment: "Add a piece: under the colours when several are picked")
                    : nil,
                identifier: "colors", focus: focus
            ) {
                ForEach(ColorName.allCases, id: \.self) { color in
                    NookChip(
                        color.title, swatch: swatch(color), isSelected: model.details.colors.contains(color)
                    ) {
                        model.toggleColor(color)
                    }
                    .accessibilityIdentifier("colour.\(color.rawValue)")
                }
            }
            EditorTextField(
                label: GarmentEditorText.label(for: .colorNote), isOptional: true,
                prompt: String(localized: "Like “Dusty rose”", bundle: .module, comment: "Add a piece: shade prompt"),
                text: $model.details.colorNote, problem: problem(.colorNote), identifier: "colorNote", focus: focus,
                focusValue: .colorNote
            )
            .id(GarmentField.colorNote)
        }
    }

    private var seasons: some View {
        EditorChoiceGroup(
            label: String(localized: "Seasons", bundle: .module, comment: "Add a piece: field label"),
            note: model.details.seasons.isEmpty
                ? String(
                    localized: "With no season picked, Style Me won’t suggest it.", bundle: .module,
                    comment: "Add a piece: under Seasons when none is picked")
                : nil,
            identifier: "seasons", focus: focus
        ) {
            ForEach(Season.allCases, id: \.self) { season in
                NookChip(season.title, isSelected: model.details.seasons.contains(season)) {
                    model.toggleSeason(season)
                }
                .accessibilityIdentifier("season.\(season.rawValue)")
            }
        }
    }

    private var occasions: some View {
        EditorChoiceGroup(
            label: String(localized: "Occasions", bundle: .module, comment: "Add a piece: field label"),
            isOptional: true, identifier: "occasions", focus: focus
        ) {
            ForEach(Occasion.allCases, id: \.self) { occasion in
                NookChip(occasion.title, isSelected: model.details.occasions.contains(occasion)) {
                    model.toggleOccasion(occasion)
                }
                .accessibilityIdentifier("occasion.\(occasion.rawValue)")
            }
        }
    }

    /// A group where exactly one chip is on.
    private func single<Value: Hashable>(
        _ label: String,
        identifier: String,
        choices: [Value],
        selection: Binding<Value>,
        title: @escaping (Value) -> String
    ) -> some View {
        EditorChoiceGroup(label: label, identifier: identifier, focus: focus) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, value in
                NookChip(title(value), isSelected: selection.wrappedValue == value) {
                    selection.wrappedValue = value
                }
                .accessibilityIdentifier("\(identifier).\(index)")
            }
        }
    }

    private func swatch(_ color: ColorName) -> Color {
        if color == .multicolor {
            return GarmentColor.multicolorStripes[0].color(in: colorScheme)
        }
        return GarmentColor.fill(for: color).color(in: colorScheme)
    }

    // MARK: Save

    private var save: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            if model.saveFailed {
                FieldProblemNote(
                    message: String(
                        localized: "That didn’t save. Your words are still here, so you can try again.",
                        bundle: .module, comment: "Add a piece: the store couldn't save")
                )
                .accessibilityIdentifier("editor.saveFailed")
            }
            NookButton(
                model.isNewPiece
                    ? String(localized: "Save to closet", bundle: .module, comment: "Button: saves a new piece")
                    : String(localized: "Save changes", bundle: .module, comment: "Button: saves an edited piece"),
                systemImage: "checkmark", isLoading: model.isSaving, fillsWidth: true, action: actions.save
            )
            .accessibilityIdentifier("editor.save")
        }
        .padding(.top, NookSpacing.small)
    }
}

/// The picture at the top of the form, what it is, and Add a photo or Change photo.
private struct PhotoRow: View {
    let model: GarmentEditorModel
    let addPhoto: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 72

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.small))
            : AnyLayout(HStackLayout(spacing: NookSpacing.medium))
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            layout {
                GarmentPicture(
                    photo: model.details.photo, category: model.details.category ?? .top,
                    colors: model.details.colors, pointSize: thumbSize * 0.8
                )
                .opacity(model.details.category == nil ? 0.45 : 1)
                .frame(width: thumbSize * 0.8, height: thumbSize * 0.8)
                .frame(width: thumbSize, height: thumbSize)
                .background(Color.nook.tint, in: NookRadius.shape(NookRadius.group))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                    Text(caption)
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("editor.photoCaption")
                    NookButton(
                        model.details.photo == .noPhoto
                            ? String(
                                localized: "Add a photo", bundle: .module, comment: "Button on the Add a piece form")
                            : String(
                                localized: "Change photo", bundle: .module, comment: "Button on the Add a piece form"),
                        systemImage: "camera", kind: .soft, size: .small, isLoading: model.photoState == .loading,
                        action: addPhoto
                    )
                    // Its ideal width, so the icon stays beside the words. The row measures it with
                    // a narrow width first, which made the button stack its icon above the words.
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                    .accessibilityIdentifier("editor.addPhoto")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.photoState == .failed {
                FieldProblemNote(
                    message: String(
                        localized: "That photo couldn’t be read. Nothing changed.", bundle: .module,
                        comment: "Add a piece form: the photo stand-in failed"))
            }
        }
    }

    private var caption: String {
        switch model.details.photo {
        case .noPhoto:
            String(localized: "No photo yet", bundle: .module, comment: "Add a piece form: the piece has no photo")
        case .sample:
            String(
                localized: "Sample photo", bundle: .module,
                comment: "Add a piece form: a sample picture stands in for a real photo until photos are built")
        case .stored:
            String(localized: "Your photo", bundle: .module, comment: "Add a piece form: her own photo")
        }
    }
}
