import DesignSystem
import Models
import SwiftUI

/// What Make your own look asks its screen to do.
struct LookBuilderActions {
    /// Opens the piece picker, on a kind when changing a piece.
    var pick: (GarmentCategory?) -> Void = { _ in }
    var save: () -> Void = {}
    var retry: () -> Void = {}
}

/// Where VoiceOver goes when the name has a problem.
enum LookBuilderFocus: Hashable {
    case name
}

/// Make your own look (`editor.html`, LR-08), top to bottom: the lead, a draft to continue if
/// there is one, the name, the live bundle with Undo and Redo, one soft row per piece with
/// Change and Remove, Add a piece, what still stops Save, and Save look.
///
/// One calm column on a phone. In a wide window (iPad, Phase 15b) the look sits on the left,
/// larger, with everything else beside it (`WidePanes`), as the mockups' tablet layout has it.
/// Rows sit on a pale tint with no edges (RD-05).
struct LookBuilderPage: View {
    @Bindable var model: LookBuilderModel
    var actions = LookBuilderActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focus: LookBuilderFocus?

    var body: some View {
        Group {
            if isStillImage {
                content
            } else {
                TourScrollReader {
                    ScrollView { content }
                        .scrollDismissesKeyboard(.immediately)
                }
            }
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            switch model.phase {
            case .loading:
                NookLoadingState(
                    String(localized: "Opening your closet", bundle: .module, comment: "Closet loading")
                )
                .readablePane()
            case .failed:
                NookErrorState(
                    String(localized: "Your closet didn’t load", bundle: .module, comment: "Closet error title"),
                    message: String(
                        localized: "Nothing was lost. Try again in a moment.", bundle: .module,
                        comment: "Closet error message"),
                    retry: actions.retry
                )
                .readablePane()
            case .loaded:
                loaded
            }
        }
        .padding(.horizontal, NookSpacing.screenMargin)
        .padding(.top, NookSpacing.small)
        .padding(.bottom, NookSpacing.xxxLarge)
        .frame(maxWidth: .infinity)
    }

    /// The look's width on a phone, and beside the pieces in a wide window.
    static let bundleWidth: CGFloat = 220
    static let wideBundleWidth: CGFloat = 320

    /// Top to bottom on a phone. Side by side, the look is alone on the left.
    private var loaded: some View {
        WidePanes(spacing: NookSpacing.medium, alignment: .leading) { isWide in
            if !isWide {
                intro
            }
            stage(width: isWide ? Self.wideBundleWidth : Self.bundleWidth)
        } trailing: { isWide in
            if isWide {
                intro
            }
            pieceRows
            NookButton(
                LookBuilderText.addPiece, systemImage: "plus", kind: .soft, fillsWidth: true,
                action: { actions.pick(nil) }
            )
            .accessibilityIdentifier("builder.add")
            .tourAnchor(LookBuilderTour.Anchor.add, label: LookBuilderText.addPiece) { actions.pick(nil) }
            saveSection
        }
    }

    /// The lead, a draft to continue, the name and where the pieces come from.
    @ViewBuilder private var intro: some View {
        Text(LookBuilderText.lead)
            .nookTextStyle(.lookTitle)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        if let draft = model.offeredDraft {
            draftCard(draft)
        }
        EditorTextField(
            label: LookBuilderText.nameLabel, isOptional: true, prompt: LookBuilderText.namePrompt,
            text: $model.name, problem: model.nameProblem.map(LookBuilderText.nameLine(for:)),
            identifier: "builder.name", focus: $focus, focusValue: .name
        )
        .tourAnchor(LookBuilderTour.Anchor.name, label: LookBuilderText.nameLabel)
        Text(LookBuilderText.source)
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Draft

    private func draftCard(_ draft: LookDraft) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Text(LookBuilderText.draftTitle)
                .nookTextStyle(.lookTitle)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(LookBuilderText.draftMessage(draft))
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("builder.draft.message")
            NookAdaptiveStack(spacing: NookSpacing.small) {
                NookButton(
                    LookBuilderText.resume, systemImage: "arrow.uturn.forward", fillsWidth: true,
                    action: model.resumeDraft
                )
                .accessibilityIdentifier("builder.draft.resume")
                NookButton(
                    LookBuilderText.startOver, systemImage: "trash", kind: .soft, fillsWidth: true,
                    action: model.discardOfferedDraft
                )
                .accessibilityHint(
                    Text(
                        "Throws away the look you didn’t save. Saved Looks don’t change.", bundle: .module,
                        comment: "Hint on Start over")
                )
                .accessibilityIdentifier("builder.draft.startOver")
            }
            .padding(.top, NookSpacing.xSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nookCard(.strong)
    }

    // MARK: The look

    private func stage(width: CGFloat) -> some View {
        let look = model.look
        let content = LookBundleContent(look: look, garments: model.garments)
        return VStack(spacing: NookSpacing.small) {
            ZStack {
                if content.pieces.isEmpty {
                    Text(LookBuilderText.emptyLook)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(NookSpacing.large)
                        .frame(maxWidth: 240)
                        .background(Color.nook.tint, in: NookRadius.shape(NookRadius.tile))
                        .accessibilityIdentifier("builder.emptyLook")
                } else {
                    LookBundle(
                        content, size: LookBundleSize(width: width),
                        title: model.name.isEmpty ? LookBuilderText.title : model.name)
                }
            }
            .frame(maxWidth: .infinity, minHeight: content.pieces.isEmpty ? 0 : LookBundleSize(width: width).height)
            if model.canUndo || model.canRedo {
                undoRedo
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var undoRedo: some View {
        NookAdaptiveStack(spacing: NookSpacing.small) {
            NookButton(
                String(localized: "Undo", bundle: .module, comment: "Toast action"),
                systemImage: "arrow.uturn.backward", kind: .soft, size: .small, fillsWidth: true,
                action: model.undo
            )
            .disabled(!model.canUndo)
            .accessibilityIdentifier("builder.undo")
            NookButton(
                String(localized: "Redo", bundle: .module, comment: "Make your own look: redoes a change"),
                systemImage: "arrow.uturn.forward", kind: .soft, size: .small, fillsWidth: true,
                action: model.redo
            )
            .disabled(!model.canRedo)
            .accessibilityIdentifier("builder.redo")
        }
        .frame(maxWidth: 360)
    }

    // MARK: Pieces

    private var pieceRows: some View {
        VStack(spacing: NookSpacing.xSmall) {
            ForEach(model.pieces) { garment in
                row(garment)
            }
        }
    }

    private func row(_ garment: Garment) -> some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.small))
            : AnyLayout(HStackLayout(spacing: NookSpacing.medium))
        return layout {
            HStack(spacing: NookSpacing.medium) {
                GarmentPicture(garment, size: CGSize(width: 44, height: 48), presentation: .sticker(.centred))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SwapText.pieceTitle(garment.category))
                        .nookTextStyle(.caption)
                        .foregroundStyle(.nook.textSecondary)
                    Text(garment.name)
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: NookSpacing.xSmall) {
                NookButton(LookBuilderText.change, kind: .pill, size: .small) {
                    actions.pick(garment.category)
                }
                .fixedSize()
                .accessibilityLabel(
                    Text(LookBuilderText.changeLabel(kind: garment.category, name: garment.name))
                )
                .accessibilityIdentifier("builder.change.\(garment.id.rawValue)")
                Button {
                    model.remove(garment.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.nook.textSecondary)
                        .frame(width: NookSpacing.minimumTapTarget, height: NookSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LookBuilderText.removeLabel(garment.name)))
                .accessibilityIdentifier("builder.remove.\(garment.id.rawValue)")
            }
        }
        .padding(.horizontal, NookSpacing.small)
        .padding(.vertical, NookSpacing.xSmall)
        .background(Color.nook.tint, in: NookRadius.shape(NookRadius.group))
        .accessibilityElement(children: .contain)
    }

    // MARK: Save

    private var saveSection: some View {
        let isSaved = model.savedLook != nil && !model.hasUnsavedChanges
        let problem = model.problems.first
        return VStack(spacing: NookSpacing.xSmall) {
            if let problem, !model.pieces.isEmpty || problem != .tooFewPieces {
                Label {
                    Text(LookBuilderText.line(for: problem, garments: model.garments))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("builder.problem")
            }
            NookButton(
                isSaved
                    ? LookBuilderText.saved
                    : (model.savedLook == nil ? LookBuilderText.save : LookBuilderText.saveChanges),
                systemImage: isSaved ? "heart.fill" : "heart",
                kind: isSaved ? .soft : .primary,
                fillsWidth: true,
                action: actions.save
            )
            .disabled(!model.canSave)
            .accessibilityHint(
                problem.map { Text(LookBuilderText.line(for: $0, garments: model.garments)) } ?? Text("")
            )
            .accessibilityIdentifier("builder.save")
            .tourAnchor(LookBuilderTour.Anchor.save, label: LookBuilderText.save) {
                if model.canSave { actions.save() }
            }
            Text(
                isSaved
                    ? LookBuilderText.savedLine
                    : model.draftSaveFailed
                        ? LookBuilderText.draftNotKept
                        : model.name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? LookBuilderText.readyLine : LookBuilderText.savedLooksFree
            )
            .nookTextStyle(.finePrint)
            .foregroundStyle(.nook.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, NookSpacing.small)
    }
}
