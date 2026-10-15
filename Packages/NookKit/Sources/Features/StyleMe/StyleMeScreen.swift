import DesignSystem
import Models
import SwiftUI

/// Where Style Me's ways forward lead. The screen that pushed Style Me supplies them, since each
/// tab has its own navigation stack.
struct StyleMeRoutes {
    /// Add a piece, from the empty closet.
    var addPiece: () -> Void = {}
    /// Suitcases, to pack an empty or small suitcase (a stand-in until Phase 13).
    var openSuitcases: () -> Void = {}
}

/// Style Me (RD-02): what the desk laptop and the calendar on Home open, and where a garment's
/// "Style me with it" goes with that piece as the starting piece.
///
/// Opening it sends nothing (RD-02.1). Each row opens its own small sheet, and only the Style me
/// button sends the request: for now it opens a stand-in that shows the request, until Phase 10b
/// builds Your looks.
struct StyleMeScreen: View {
    /// Opens on the Occasion sheet, as the calendar on Home does.
    var choosingOccasion = false
    var routes = StyleMeRoutes()

    @Environment(\.services) private var services
    @Environment(\.locale) private var locale
    @State private var model: StyleMeModel
    @State private var sheet: StyleMeSheet?
    @State private var sent: StyleRequestSummary?
    @State private var askedForOccasion = false

    init(startingPieceID: Garment.ID? = nil, choosingOccasion: Bool = false, routes: StyleMeRoutes = StyleMeRoutes()) {
        self.choosingOccasion = choosingOccasion
        self.routes = routes
        _model = State(initialValue: StyleMeModel(startingPieceID: startingPieceID))
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
        .navigationDestination(item: $sent) { summary in
            StyleRequestSummaryScreen(summary: summary)
        }
        .task {
            // Runs again when she comes back from a pushed screen (Add a piece, the stand-in
            // results), which picks up any change and keeps her choices.
            await model.load(from: services)
            openOccasionIfAsked()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: StyleMeSheet) -> some View {
        let sourceName = model.text(locale: locale).sourceName
        switch sheet {
        case .source: SourceChoices(model: model, close: close)
        case .occasion: OccasionChoices(model: model, close: close)
        case .startingPiece: StartingPieceChoices(model: model, sourceName: sourceName, close: close)
        case .comfort: ComfortChoices(model: model, close: close)
        case .color: ColorChoices(model: model)
        case .preferences: PreferencesChoices(model: model, sourceName: sourceName, close: close)
        }
    }

    private func close() {
        sheet = nil
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
        case .addPieces: routes.openSuitcases()
        case .chooseSource: sheet = .source
        case .chooseStartingPiece: sheet = .startingPiece
        case .clearStartingPiece: model.update { $0.startingPieceID = nil }
        case .chooseOccasion: sheet = .occasion
        case .makeColorPreferred: model.update { $0.color?.strength = .preferred }
        }
    }

    /// Style me: the request goes to the stand-in results. Nothing else sends it (RD-02.1).
    private func styleMe() {
        guard let request = model.makeRequest() else { return }
        let text = model.text(locale: locale)
        sent = StyleRequestSummary(
            request: request, sourceName: text.sourceName, startingPieceName: model.startingPiece?.name,
            occasionValue: text.occasionValue, locale: locale)
    }
}

#Preview {
    NavigationStack {
        StyleMeScreen()
    }
}
