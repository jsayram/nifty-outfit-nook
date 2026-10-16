import DesignSystem
import Models
import SwiftUI

/// Where Style Me's ways forward lead. The screen that pushed Style Me supplies them, since each
/// tab has its own navigation stack.
struct StyleMeRoutes {
    /// Add a piece, from the empty closet.
    var addPiece: () -> Void = {}
    /// Suitcases, to choose or pack a suitcase.
    var openSuitcases: () -> Void = {}
    /// One suitcase, to pack it when it's empty or small (Phase 13).
    var openSuitcase: (Suitcase.ID, String) -> Void = { _, _ in }
}

/// Style Me (RD-02): what the desk laptop and the calendar on Home open, and where a garment's
/// "Style me with it" goes with that piece as the starting piece.
///
/// Opening it sends nothing (RD-02.1). Each row opens its own small sheet, and only the Style me
/// button sends the request, by opening Your looks (Phase 10b).
struct StyleMeScreen: View {
    /// Opens on the Occasion sheet, as the calendar on Home does.
    var choosingOccasion = false
    var routes = StyleMeRoutes()

    @Environment(\.services) private var services
    @Environment(\.locale) private var locale
    @State private var model: StyleMeModel
    @State private var sheet: StyleMeSheet?
    @State private var sent: StyleRequest?
    @State private var askedForOccasion = false

    /// - Parameter source: a suitcase's "Style me from this suitcase" (Phase 13). Without it,
    ///   Style Me starts from the source she chose last.
    init(
        startingPieceID: Garment.ID? = nil, source: WardrobeSource? = nil, choosingOccasion: Bool = false,
        routes: StyleMeRoutes = StyleMeRoutes()
    ) {
        self.choosingOccasion = choosingOccasion
        self.routes = routes
        _model = State(initialValue: StyleMeModel(startingPieceID: startingPieceID, source: source))
    }

    var body: some View {
        StyleMePage(
            model: model,
            actions: StyleMeActions(
                retry: { Task { await model.load(from: services) } },
                open: { sheet = $0 },
                perform: perform,
                styleMe: styleMe
            )
        )
        .navigationTitle(HomeDestination.styleMe(choosingOccasion: false).title)
        .navigationBarTitleDisplayMode(.inline)
        .nookSheet(
            item: $sheet,
            title: { $0.title },
            subtitle: { $0.subtitle(sourceName: model.text(locale: locale).sourceName) }
        ) { sheet in
            sheetContent(sheet)
        }
        .navigationDestination(item: $sent) { request in
            YourLooksScreen(request: request, routes: resultRoutes)
        }
        .task {
            // Runs again when she comes back from a pushed screen (Add a piece, Your looks),
            // which picks up any change and keeps her choices.
            await model.load(from: services)
            openOccasionIfAsked()
        }
        // Style Me's quick tour (Phase 16b), on her first visit, once the request is on screen.
        // From the calendar it waits until the Occasion sheet has closed.
        .screenTour(
            StyleMeTour.definition,
            isReady: model.phase == .loaded && !model.check.issues.contains(.closetEmpty) && sheet == nil
                && sent == nil)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: StyleMeSheet) -> some View {
        let sourceName = model.text(locale: locale).sourceName
        switch sheet {
        // A source or occasion she picks is remembered for next time (FR-67, Phase 13).
        case .source: SourceChoices(model: model, close: closeAndRemember)
        case .occasion: OccasionChoices(model: model, close: closeAndRemember)
        case .startingPiece: StartingPieceChoices(model: model, sourceName: sourceName, close: close)
        case .comfort: ComfortChoices(model: model, close: close)
        case .color: ColorChoices(model: model)
        case .preferences: PreferencesChoices(model: model, sourceName: sourceName, close: close)
        }
    }

    private func close() {
        sheet = nil
    }

    private func closeAndRemember() {
        sheet = nil
        remember()
    }

    private func remember() {
        Task { await model.remember(in: services) }
    }

    /// The calendar on Home asks for the occasion once, when the screen first has its data.
    private func openOccasionIfAsked() {
        guard choosingOccasion, !askedForOccasion, model.phase == .loaded,
            !model.check.issues.contains(.closetEmpty)
        else { return }
        askedForOccasion = true
        sheet = .occasion
    }

    private func perform(_ action: StyleMeNoticeAction) {
        switch action {
        case .addPiece: routes.addPiece()
        case .addPieces: openSuitcase(of: model.draft.source)
        case .chooseSource: sheet = .source
        case .chooseStartingPiece: sheet = .startingPiece
        case .clearStartingPiece: model.update { $0.startingPieceID = nil }
        case .chooseOccasion: sheet = .occasion
        case .makeColorPreferred: model.update { $0.color?.strength = .preferred }
        }
    }

    /// Style me: opens Your looks, which sends the request. Nothing else sends it (RD-02.1).
    private func styleMe() {
        guard let request = model.makeRequest() else { return }
        remember()
        sent = request
    }

    /// The suitcase to pack, or Suitcases when it can't be found.
    private func openSuitcase(of source: WardrobeSource) {
        if let suitcase = model.suitcase, suitcase.id == source.suitcaseID {
            routes.openSuitcase(suitcase.id, suitcase.name)
        } else {
            routes.openSuitcases()
        }
    }

    /// Your looks' ways back: to Style Me with her choices kept, or on to adding pieces.
    private var resultRoutes: YourLooksRoutes {
        YourLooksRoutes(
            backToStyleMe: { sent = nil },
            useMainCloset: {
                model.choose(source: .mainCloset)
                remember()
                sent = nil
            },
            addPieces: { source in
                sent = nil
                if source.isSuitcase { openSuitcase(of: source) } else { routes.addPiece() }
            }
        )
    }
}

#Preview {
    NavigationStack {
        StyleMeScreen()
    }
}
