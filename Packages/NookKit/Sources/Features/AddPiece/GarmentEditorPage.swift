import DesignSystem
import Models
import SwiftUI

/// What the Add a piece and Edit buttons do. The screen fills these in; snapshot tests leave
/// them empty.
struct GarmentEditorActions {
    var retry: () -> Void = {}
    var close: () -> Void = {}
    var resume: () -> Void = {}
    var discardDraft: () -> Void = {}
    var choosePhoto: (PhotoSource) -> Void = { _ in }
    var tryAnotherPhoto: () -> Void = {}
    var describeInWords: () -> Void = {}
    var suggest: () -> Void = {}
    var continueFromWords: () -> Void = {}
    var addPhoto: () -> Void = {}
    var save: () -> Void = {}
}

/// Add a piece and Edit, top to bottom: the step's title and line, then the step itself (the
/// choices, Describe in words, or the details form), or "Continue where you left off?".
///
/// Separate from `GarmentEditorScreen` so snapshot tests can draw it from a model.
struct GarmentEditorPage: View {
    @Bindable var model: GarmentEditorModel
    var actions = GarmentEditorActions()
    /// The clock for "Last changed 5 minutes ago". Snapshot tests fix it.
    var now: Date = .now

    @Environment(\.closetIsStillImage) private var isStillImage
    @AccessibilityFocusState private var focusedField: GarmentField?

    /// Past this the form reads badly; iPad's own layout comes in Phase 15a.
    static let maximumWidth: CGFloat = 560

    var body: some View {
        if isStillImage {
            page
                .background(Color.nook.wallGradient)
        } else {
            ScrollViewReader { proxy in
                TourScrollReader {
                    ScrollView(.vertical) {
                        page
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .background(Color.nook.wallGradient.ignoresSafeArea())
                .onChange(of: model.problemCheckCount) {
                    showProblems(scrolling: proxy)
                }
            }
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            header
            content
        }
        .padding(.horizontal, NookSpacing.screenMargin)
        .padding(.top, NookSpacing.small)
        .padding(.bottom, NookSpacing.xxxLarge)
        .readablePane(maxWidth: Self.maximumWidth)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            Text(title)
                .nookTextStyle(.display)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("editor.title")
            if let lead {
                Text(lead)
                    .nookTextStyle(.body)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(
                String(localized: "Opening this piece", bundle: .module, comment: "Garment detail loading")
            )
            .padding(.top, NookSpacing.xLarge)
        case .failed:
            NookErrorState(
                String(localized: "This piece didn’t load", bundle: .module, comment: "Garment detail error title"),
                message: String(
                    localized: "Nothing was lost. Try again in a moment.", bundle: .module,
                    comment: "Closet error message"),
                retry: actions.retry
            )
            .padding(.top, NookSpacing.xLarge)
        case .gone:
            NookEmptyState(
                String(
                    localized: "This piece isn’t in your closet any more", bundle: .module,
                    comment: "Garment detail: the piece was deleted elsewhere"),
                message: String(
                    localized: "Deleted pieces stay in Recently deleted for 30 days.", bundle: .module,
                    comment: "Garment detail: where a deleted piece went"),
                systemImage: "hanger"
            ) {
                NookButton(
                    String(localized: "Back to Closet", bundle: .module, comment: "Button: goes back to Closet"),
                    systemImage: "chevron.left", kind: .soft, fillsWidth: true, action: actions.close
                )
                .accessibilityIdentifier("editor.gone.back")
            }
            .padding(.top, NookSpacing.xLarge)
        case .offeringResume:
            if let draft = model.pendingDraft {
                DraftResumeCard(
                    draft: draft, now: now, identifier: "draft", resume: actions.resume, discard: actions.discardDraft)
            }
        case .editing:
            switch model.step {
            case .choose:
                AddPieceChoices(model: model, actions: actions)
            case .words:
                DescribeInWords(model: model, actions: actions, focus: $focusedField)
            case .details:
                GarmentDetailsForm(model: model, actions: actions, focus: $focusedField)
            }
        }
    }

    /// After Save found problems: VoiceOver says which fields, moves to the first one, and the
    /// page scrolls to it.
    private func showProblems(scrolling proxy: ScrollViewProxy) {
        guard let first = model.problems.fields.first else { return }
        AccessibilityNotification.Announcement(GarmentEditorText.problemsAnnouncement(model.problems)).post()
        proxy.scrollTo(first, anchor: .top)
        focusedField = first
    }

    // MARK: Words

    private var title: String {
        if !model.isNewPiece {
            return String(localized: "Edit piece", bundle: .module, comment: "Screen title")
        }
        guard model.phase == .editing else {
            return String(localized: "Add a piece", bundle: .module, comment: "Screen title")
        }
        switch model.step {
        case .choose: return String(localized: "Add a piece", bundle: .module, comment: "Screen title")
        case .words: return String(localized: "Describe it", bundle: .module, comment: "Add a piece: words step title")
        case .details:
            return String(localized: "About this piece", bundle: .module, comment: "Add a piece: details step title")
        }
    }

    private var lead: String? {
        guard model.phase == .editing else { return nil }
        if !model.isNewPiece {
            return String(
                localized: "Change anything, then save. Nothing changes until you do.", bundle: .module,
                comment: "Edit piece: line under the title")
        }
        switch model.step {
        case .choose:
            return String(
                localized: "How would you like to add it?", bundle: .module,
                comment: "Add a piece: line under the title")
        case .words:
            return String(
                localized: "Say it the way you would to a friend.", bundle: .module,
                comment: "Describe in words: line under the title")
        case .details:
            return String(
                localized: "Only a name and the kind of piece are needed. Everything else can wait.", bundle: .module,
                comment: "Add a piece details: line under the title")
        }
    }
}
