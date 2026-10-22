import DesignSystem
import Models
import SwiftUI

/// What Your looks asks its screen to do.
struct YourLooksActions {
    var toggleSave: (Look) -> Void = { _ in }
    var tryOn: (Look) -> Void = { _ in }
    var swap: (Look) -> Void = { _ in }
    /// Undo for the latest swap or removal (Phase 11).
    var undoChange: () -> Void = {}
    var askStylist: (Look) -> Void = { _ in }
    var findOne: (LookBundlePiece) -> Void = { _ in }
    var tryDifferentOutfit: () -> Void = {}
    var retry: () -> Void = {}
    var cancel: () -> Void = {}
    var backToStyleMe: () -> Void = {}
    var useMainCloset: () -> Void = {}
    var addPieces: () -> Void = {}
    var openSaved: (Look) -> Void = { _ in }
    var reloadSaved: () -> Void = {}
    /// 27a: opens the stylist's consent text.
    var reviewConsent: () -> Void = {}
    /// Release: Sign in beside Quick ideas, after she said Not now to signing in.
    var signIn: () -> Void = {}
    /// Release (guideline 1.2): Report a problem on the stylist's look or its why line: the
    /// result, and what she may say it's about.
    var report: (AIReportTarget, [AIReportSubject]) -> Void = { _, _ in }
}

/// Your looks (`results-versions.html`, LR-05a, LR-06): the Today and Saved tabs, then the
/// result, its styling progress, or a state that says plainly what happened and what to do.
///
/// One calm column on a phone. In a wide window (Phase 15b) the result's look sits beside its
/// pieces and buttons, the Saved tab's looks fill the width, and the states keep to a readable
/// column in the middle.
struct YourLooksPage: View {
    let model: YourLooksModel
    var actions = YourLooksActions()

    @Environment(\.locale) private var locale
    @Environment(\.closetIsStillImage) private var isStillImage

    var body: some View {
        Group {
            if isStillImage {
                content
            } else {
                TourScrollReader {
                    ScrollView { content }
                }
            }
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
    }

    private var text: YourLooksText {
        YourLooksText(request: model.request, suitcaseName: model.suitcaseName, locale: locale)
    }

    private var content: some View {
        VStack(spacing: NookSpacing.large) {
            tabs
            switch model.tab {
            case .today: today
            case .saved: SavedLooksTab(model: model, text: text, actions: actions)
            }
        }
        .padding(.horizontal, NookSpacing.screenMargin)
        .padding(.top, NookSpacing.small)
        .padding(.bottom, NookSpacing.xxxLarge)
        .frame(maxWidth: .infinity)
    }

    /// Today and Saved (LR-06), a small switch at the top.
    private var tabs: some View {
        NookSegmentedPicker(
            String(localized: "Which looks", bundle: .module, comment: "VoiceOver name of the Today and Saved switch"),
            selection: Binding(get: { model.tab }, set: { model.tab = $0 }),
            options: YourLooksModel.Tab.allCases.map { tab in
                .init(tab, title: YourLooksText.title(of: tab), identifier: "results.tab.\(tab.rawValue)")
            }
        )
        .frame(maxWidth: 320)
    }

    @ViewBuilder
    private var today: some View {
        switch model.status {
        case .notStarted, .styling:
            StylingProgress(model: model, text: text, cancel: actions.cancel)
                .readablePane()
        case .showing:
            TodayResult(model: model, text: text, actions: actions)
        case .insufficient(let wardrobe):
            InsufficientState(wardrobe: wardrobe, usablePieces: model.usablePieces, text: text, actions: actions)
                .readablePane()
        case .failed(let failure):
            FailureState(failure: failure, actions: actions, openSaved: { model.tab = .saved })
                .readablePane()
        }
    }
}
