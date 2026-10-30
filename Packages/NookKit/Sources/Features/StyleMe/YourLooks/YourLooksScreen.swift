import DesignSystem
import Models
import SwiftUI

/// Where Your looks' ways out lead. Style Me, which pushed it, supplies them.
struct YourLooksRoutes {
    /// Back to Style Me with every choice kept.
    var backToStyleMe: () -> Void = {}
    /// Back to Style Me with the source set to Main closet (a partial result from a suitcase).
    var useMainCloset: () -> Void = {}
    /// Add a piece, or a suitcase's pieces, when the source can't make a look.
    var addPieces: (WardrobeSource) -> Void = { _ in }
}

/// Your looks: what Style me opens (LR-05a, LR-05b, LR-06, RD-06).
///
/// The request goes to the stylist when the screen first appears, and leaving the screen
/// cancels it if it's still running. Saving happens here, with Undo. Swap a piece opens Swap
/// (Phase 11), and its changes come back here with Undo. Try it on opens its sheet (Phase 12b),
/// which saves the look first if it isn't saved, and See the picture opens it on Saved Looks.
/// Ask stylist and Find one open stand-ins until their phases (later, 34).
struct YourLooksScreen: View {
    var routes = YourLooksRoutes()

    @Environment(\.services) private var services
    /// Phase 28: the router sends nothing to the cloud while the phone is offline.
    @Environment(\.connection) private var connection
    @Environment(\.locale) private var locale
    @Environment(\.openInSavedLooks) private var openInSavedLooks
    @State private var model: YourLooksModel
    @State private var stub: ResultStub?
    @State private var tryingOn: TryOnRoute?
    @State private var toast: NookToastMessage?
    @State private var swapping: SwapRoute?
    /// 27a: the stylist's consent sheet, from Review.
    @State private var showsConsent = false
    /// F1c: Styling access, when the server shows none for her account.
    @State private var showsStylingAccess = false
    /// Release: Report a problem, open for a result.
    @State private var reporting: AIReportRoute?
    @Environment(\.signIn) private var signIn
    @Environment(\.signInAgain) private var signInAgain

    init(request: StyleRequest, routes: YourLooksRoutes = YourLooksRoutes()) {
        self.routes = routes
        _model = State(initialValue: YourLooksModel(request: request))
    }

    var body: some View {
        YourLooksPage(
            model: model,
            actions: YourLooksActions(
                toggleSave: toggleSave,
                tryOn: openTryOn,
                swap: { _ in openSwap() },
                undoChange: undoChange,
                askStylist: { stub = .askStylist($0.id) },
                findOne: { stub = .findOne(pieceName: $0.name) },
                tryDifferentOutfit: { model.tryDifferentOutfit() },
                retry: { model.retry() },
                cancel: cancel,
                backToStyleMe: routes.backToStyleMe,
                useMainCloset: routes.useMainCloset,
                addPieces: { routes.addPieces(model.request.source) },
                openSaved: { stub = .saved($0.id) },
                reloadSaved: { Task { await model.reloadLooks() } },
                reviewConsent: { showsConsent = true },
                signIn: {
                    Task { if await signInAgain(.styling) { model.retry() } }
                },
                seeStylingAccess: { showsStylingAccess = true },
                report: { target, subjects in
                    reporting = AIReportRoute(
                        target: target, subjects: subjects, hide: { Task { await model.hideResult() } })
                }
            )
        )
        .aiReportSheet($reporting)
        .nookSheet(isPresented: $showsConsent, title: StylistConsentText.title, detents: [.large]) {
            StylistConsentSheet(
                allow: {
                    showsConsent = false
                    model.agreeToStylist()
                },
                notNow: { showsConsent = false })
        }
        // F1c: after Styling access closes, the stylist is asked again; without access the
        // server refuses again, and nothing is counted either way.
        .sheet(isPresented: $showsStylingAccess, onDismiss: { model.retry() }) {
            NavigationStack {
                StylingAccessScreen(isSheet: true)
            }
            .signInGate()
        }
        .navigationTitle(Text("Your looks", bundle: .module, comment: "Screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .nookSheet(item: $stub, title: { sheetTitle($0) }, subtitle: { $0.subtitle }) { stub in
            sheetContent(stub)
        }
        .tryOnSheet($tryingOn, seePicture: { openInSavedLooks([.picture($0.id)]) })
        .navigationDestination(item: $swapping) { route in
            SwapScreen(model: route.model, finish: finishSwap)
        }
        // The page's scroll view runs under the floating tab bar, so the toast sits on a clear
        // layer that keeps to the safe area and stays above the tab bar.
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task {
            model.signIn = signIn
            model.start(with: services, connection: connection)
        }
        // Your looks' quick tour (Phase 16b), once the looks are ready on the Today tab, with no
        // problem banner, sheet or toast over them.
        .screenTour(
            YourLooksTour.definition(hasVersions: model.versions.count > 1),
            isReady: model.status == .showing && model.result != nil && model.tab == .today && model.problem == nil
                && stub == nil && tryingOn == nil && swapping == nil && toast == nil
        )
        .onDisappear {
            // Leaving stops Stage A's stylist on the phone. A cloud request keeps running apart
            // from this screen and lands in her history (27a; AI work isn't tied to a screen).
            model.leave()
        }
        .onChange(of: model.status) { old, new in
            announce(from: old, to: new)
        }
        .onChange(of: model.version) {
            guard let look = model.currentLook else { return }
            let title = YourLooksText.title(of: model.shownVersion)
            let description = YourLooksText.description(of: model.shownVersion, hasIdea: !look.ideas.isEmpty)
            AccessibilityNotification.Announcement("\(title). \(description)").post()
        }
    }

    // MARK: Sheets

    private func sheetTitle(_ stub: ResultStub) -> String {
        if case .saved(let id) = stub, let name = model.looks.first(where: { $0.id == id })?.name {
            return name
        }
        return stub.title
    }

    @ViewBuilder
    private func sheetContent(_ stub: ResultStub) -> some View {
        if case .saved(let id) = stub, let look = model.looks.first(where: { $0.id == id }) {
            SavedLookSheet(look: look, garments: model.garments) { piece in
                self.stub = .findOne(pieceName: piece.name)
            }
        } else {
            ResultStubContent(stub: stub)
        }
    }

    // MARK: Actions

    private func cancel() {
        let hadResult = model.result != nil
        model.cancel()
        if !hadResult { routes.backToStyleMe() }
    }

    private func toggleSave(_ look: Look) {
        let text = YourLooksText(request: model.request, suitcaseName: model.suitcaseName, locale: locale)
        let name = text.name(for: look, garments: model.garments)
        Task {
            do {
                let change = try await model.toggleSave(look, name: name)
                let message: String =
                    switch change {
                    case .saved: YourLooksText.saved
                    case .unsaved: YourLooksText.unsaved
                    }
                toast = NookToastMessage(
                    message, systemImage: change == .saved(look.id) ? "heart.fill" : "heart",
                    actionTitle: YourLooksText.undo,
                    action: { undo(change, name: name) })
            } catch {
                toast = NookToastMessage(YourLooksText.saveFailed, systemImage: "exclamationmark.circle")
            }
        }
    }

    // MARK: Try it on

    /// Try it on for the version on screen. A look that isn't saved yet is saved when the picture
    /// is made, under the name Save look would give it, and the sheet says so first.
    private func openTryOn(_ look: Look) {
        let text = YourLooksText(request: model.request, suitcaseName: model.suitcaseName, locale: locale)
        let name = model.stored(look)?.name ?? text.name(for: look, garments: model.garments)
        let model = model
        let saveLook: (() async throws(StoreError) -> Look)? =
            model.isSaved(look)
            ? nil
            : { () async throws(StoreError) -> Look in try await model.saveForPicture(look, name: name) }
        tryingOn = TryOnRoute(
            model: TryOnModel(look: look, lookName: name, garments: model.garments, saveLook: saveLook))
    }

    // MARK: Swap a piece

    private func openSwap() {
        let text = YourLooksText(request: model.request, suitcaseName: model.suitcaseName, locale: locale)
        guard let swap = model.swapModel(sourceName: text.sourceName) else { return }
        swapping = SwapRoute(model: swap)
    }

    /// Use this top or Remove this piece: back to the look, changed, with Undo (LR-08.2).
    private func finishSwap(_ outcome: SwapOutcome) {
        let message: String
        switch outcome {
        case .swapped(let look, let name):
            model.apply(look)
            message = SwapText.swapped(name)
        case .removed(let look, let name):
            model.apply(look)
            message = SwapText.removed(name)
        }
        swapping = nil
        toast = NookToastMessage(
            message, systemImage: "arrow.left.arrow.right", actionTitle: YourLooksText.undo, action: undoChange)
    }

    private func undoChange() {
        guard model.undoChange() else { return }
        toast = NookToastMessage(SwapText.undone, systemImage: "arrow.uturn.backward")
    }

    private func undo(_ change: YourLooksModel.SaveChange, name: String) {
        Task {
            do {
                try await model.undo(change, name: name)
            } catch {
                toast = NookToastMessage(YourLooksText.saveFailed, systemImage: "exclamationmark.circle")
            }
        }
    }

    /// Says when the looks are ready, or what happened, for VoiceOver.
    private func announce(from old: YourLooksModel.Status, to new: YourLooksModel.Status) {
        guard case .styling = old else { return }
        let message: String? =
            switch new {
            case .showing:
                model.problem == nil
                    ? String(localized: "Your looks are ready.", bundle: .module, comment: "VoiceOver announcement")
                    : nil
            case .insufficient:
                String(
                    localized: "Not enough pieces for a look", bundle: .module,
                    comment: "Your looks: insufficient wardrobe")
            case .failed(.offline):
                String(
                    localized: "Styling needs a connection", bundle: .module, comment: "Your looks offline state title")
            case .failed(.notCompleted):
                String(localized: "Styling didn’t finish", bundle: .module, comment: "Your looks failed state title")
            default:
                nil
            }
        if let message { AccessibilityNotification.Announcement(message).post() }
    }
}

/// Swap a piece on the navigation stack. Pushed by identity: each opening is a new Swap.
struct SwapRoute: Hashable, Identifiable {
    let id = UUID()
    let model: SwapModel

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
