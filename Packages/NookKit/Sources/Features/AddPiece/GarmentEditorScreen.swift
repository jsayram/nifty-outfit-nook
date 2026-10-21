import DesignSystem
import Models
import SwiftUI

/// Add a piece and Edit (Phase 7b), pushed from Closet and from garment detail's Edit.
///
/// The bar has Back (to the previous step) or Cancel, and Save on the details form. Cancel with
/// unsaved work asks first. Save hands the piece back to Closet, which closes the form and
/// shows a toast. The draft is written as she goes and when the app leaves the foreground, so
/// work survives the app being closed.
struct GarmentEditorScreen: View {
    let saved: (GarmentEditorModel.Saved) -> Void
    let close: () -> Void

    @Environment(\.services) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: GarmentEditorModel
    @State private var confirmsDiscard = false
    @State private var choosesPhotoSource = false
    /// The system camera and photo picker, when real photos are on (Phase 22a).
    @State private var picking = PhotoPickingModel()

    init(
        target: GarmentDraft.Target,
        firstStep: GarmentDraft.Step = .choose,
        resumesDraft: Bool = false,
        saved: @escaping (GarmentEditorModel.Saved) -> Void,
        close: @escaping () -> Void
    ) {
        self.saved = saved
        self.close = close
        _model = State(
            initialValue: GarmentEditorModel(target: target, firstStep: firstStep, resumesDraft: resumesDraft))
    }

    var body: some View {
        GarmentEditorPage(model: model, actions: actions)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                // The title is on the page instead.
                ToolbarItem(placement: .principal) {
                    Text(verbatim: "").accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarLeading) {
                    leadingButton
                }
                if model.phase == .editing && model.step == .details {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: save) {
                            Text("Save", bundle: .module, comment: "Toolbar button: saves the piece")
                                .padding(.horizontal, NookSpacing.xSmall)
                        }
                        .disabled(model.isSaving)
                        .accessibilityIdentifier("editor.toolbarSave")
                        .tourAnchor(
                            EditPieceTour.Anchor.save,
                            label: String(
                                localized: "Save", bundle: .module, comment: "Toolbar button: saves the piece"),
                            action: save)
                    }
                }
            }
            // An alert rather than a confirmation dialog: on iOS 26 the dialog opens as a popover
            // from the bar with no visible Keep editing, and she should see both choices.
            .alert(discardTitle, isPresented: $confirmsDiscard) {
                Button(role: .destructive, action: discardAndClose) {
                    Text(
                        model.isNewPiece
                            ? String(localized: "Discard this piece", bundle: .module, comment: "Confirm button")
                            : String(localized: "Discard changes", bundle: .module, comment: "Confirm button"))
                }
                Button(role: .cancel) {
                } label: {
                    Text("Keep editing", bundle: .module, comment: "Button: closes the discard question")
                }
            } message: {
                Text(discardMessage)
            }
            .confirmationDialog(
                String(localized: "Add a photo", bundle: .module, comment: "Photo source question"),
                isPresented: $choosesPhotoSource, titleVisibility: .visible
            ) {
                ForEach(model.photoSources.filter { !(model.usesSystemPicker && $0 == .paste) }, id: \.self) { source in
                    Button(Self.title(for: source)) { choosePhoto(source) }
                }
            } message: {
                if !model.usesSystemPicker {
                    Text(
                        "For now each choice adds a sample picture.", bundle: .module,
                        comment: "Photo source question while photos are a stand-in")
                }
            }
            .photoPicking(picking) { picked in
                let intake = services.photos
                Task { await model.keepPhoto(picked, using: intake) }
            }
            .task { await model.load(from: services) }
            // Add a piece's quick tour (Phase 16b), on its first step only: the photo choices and
            // Describe in words.
            .screenTour(
                AddPieceTour.definition,
                isReady: model.isNewPiece && model.phase == .editing && model.step == .choose && !confirmsDiscard
                    && !choosesPhotoSource && picking.step == nil
            )
            // Editing a piece she has has its own tour (Stage A audit): the photo, the details and
            // Save. Not over the card that offers to carry on with a draft.
            .screenTour(
                EditPieceTour.definition,
                isReady: !model.isNewPiece && model.phase == .editing && model.step == .details
                    && model.pendingDraft == nil && !confirmsDiscard && !choosesPhotoSource && picking.step == nil
            )
            .onChange(of: scenePhase) { _, phase in
                // Don't wait for the app to be closed: write the draft as soon as it leaves the
                // foreground (PRD 7.3).
                if phase != .active { Task { await model.saveDraftNow() } }
            }
    }

    @ViewBuilder private var leadingButton: some View {
        if model.phase == .editing, model.previousStep != nil {
            Button {
                model.goBack()
            } label: {
                HStack(spacing: NookSpacing.xxSmall) {
                    Image(systemName: "chevron.left")
                    Text("Back", bundle: .module, comment: "Button: the previous step of Add a piece")
                }
                .padding(.horizontal, NookSpacing.xxSmall)
            }
            .accessibilityIdentifier("editor.back")
        } else {
            Button(action: cancel) {
                Text("Cancel", bundle: .module, comment: "Button: closes Add a piece or Edit")
                    .padding(.horizontal, NookSpacing.xSmall)
            }
            .accessibilityIdentifier("editor.cancel")
        }
    }

    private var actions: GarmentEditorActions {
        GarmentEditorActions(
            retry: { Task { await model.load(from: services) } },
            close: close,
            resume: { model.resume() },
            discardDraft: { Task { await model.discardPendingDraft() } },
            choosePhoto: choosePhoto,
            pastePhoto: { picked in
                let intake = services.photos
                Task { await model.keepPhoto(picked, using: intake) }
            },
            tryAnotherPhoto: { model.clearPhotoProblem() },
            describeInWords: { model.describeInWords() },
            suggest: {
                let reader = services.descriptions
                Task { await model.suggest(using: reader) }
            },
            continueFromWords: { model.continueFromWords() },
            addPhoto: { choosesPhotoSource = true },
            save: save
        )
    }

    private var navigationTitle: String {
        model.isNewPiece
            ? String(localized: "Add a piece", bundle: .module, comment: "Screen title")
            : String(localized: "Edit piece", bundle: .module, comment: "Screen title")
    }

    private var discardTitle: String {
        model.isNewPiece
            ? String(localized: "Discard this piece?", bundle: .module, comment: "Question before closing Add a piece")
            : String(localized: "Discard your changes?", bundle: .module, comment: "Question before closing Edit")
    }

    private var discardMessage: String {
        if model.isNewPiece {
            return String(
                localized: "What you’ve filled in so far won’t be kept.", bundle: .module,
                comment: "Add a piece: under the discard question")
        }
        let name = model.savedName ?? ""
        return String(
            localized: "\(name) stays as it was.", bundle: .module,
            comment: "Edit: under the discard question, with the piece's saved name")
    }

    private static func title(for source: PhotoSource) -> String {
        switch source {
        case .camera: String(localized: "Take photo", bundle: .module, comment: "Add a piece choice")
        case .library: String(localized: "Choose from Photos", bundle: .module, comment: "Add a piece choice")
        case .paste: String(localized: "Paste", bundle: .module, comment: "Add a piece choice")
        }
    }

    // MARK: Actions

    /// Cancel: closes at once when there's nothing to lose, otherwise asks first. While
    /// "Continue where you left off?" shows, the draft stays for next time.
    private func cancel() {
        if model.phase == .editing && model.isDirty {
            confirmsDiscard = true
        } else {
            close()
        }
    }

    private func discardAndClose() {
        Task {
            await model.discardChanges()
            close()
        }
    }

    private func choosePhoto(_ source: PhotoSource) {
        if model.usesSystemPicker {
            picking.start(source)
            return
        }
        let intake = services.photos
        Task { await model.choosePhoto(from: source, using: intake) }
    }

    private func save() {
        let closet = services.closet
        Task {
            if let result = await model.save(in: closet) {
                saved(result)
            }
        }
    }
}
