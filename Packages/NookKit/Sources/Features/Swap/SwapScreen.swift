import DesignSystem
import Models
import SwiftUI

/// What Swap a piece hands back to the screen that opened it.
enum SwapOutcome: Equatable {
    /// Use this top: the changed look and the new piece's name, for the toast.
    case swapped(Look, pieceName: String)
    /// Remove this piece: the look without it and the piece's name.
    case removed(Look, pieceName: String)
}

/// Swap a piece, pushed from Your looks (LR-07, LR-08). Opening it, choosing a piece and Show 3
/// more send nothing. See all opens her pieces of that kind in a sheet with Closet's search and
/// filters; choosing one there tries it in the look. Find one opens the stand-in until Phase 34.
///
/// Use this top and Remove this piece hand the changed look back through `finish`; the screen
/// that opened Swap goes back and offers Undo there. Keep current puts the look back as it is,
/// and Back leaves it unchanged.
struct SwapScreen: View {
    let finish: (SwapOutcome) -> Void

    @State private var model: SwapModel
    @State private var seeAll: ClosetModel?
    @State private var showsFindOne = false

    init(model: SwapModel, finish: @escaping (SwapOutcome) -> Void) {
        _model = State(initialValue: model)
        self.finish = finish
    }

    var body: some View {
        SwapPage(
            model: model,
            actions: SwapActions(
                use: use,
                keep: { model.keepCurrent() },
                remove: remove,
                seeAll: openSeeAll,
                findOne: { showsFindOne = true }
            )
        )
        .navigationTitle(Text("Swap a piece", bundle: .module, comment: "Results button (RD-06, LR-08)"))
        .navigationBarTitleDisplayMode(.inline)
        .nookSheet(
            item: $seeAll,
            title: { _ in SwapText(category: model.category, sourceName: model.setup.sourceName).seeAllTitle },
            detents: [.large]
        ) { picker in
            let text = SwapText(category: model.category, sourceName: model.setup.sourceName)
            PiecePicker(
                model: picker,
                lead: text.seeAllLead,
                prompt: String(
                    localized: "Search these pieces", bundle: .module, comment: "Search prompt in a piece picker"),
                hint: String(localized: "Shows it in the look.", bundle: .module, comment: "Swap: hint on an option"),
                emptyTitle: text.nothingElse,
                emptyMessage: ""
            ) { id in
                model.select(id)
                seeAll = nil
            }
        }
        .nookSheet(
            isPresented: $showsFindOne,
            title: String(localized: "Find one", bundle: .module, comment: "Button on a look's piece she doesn't own")
        ) {
            ResultStubContent(stub: .findOne(pieceName: ""))
        }
    }

    private func use() {
        guard let preview = model.preview, let look = model.swapped() else { return }
        finish(.swapped(look, pieceName: model.setup.garments[preview]?.name ?? ""))
    }

    private func remove() {
        guard let piece = model.piece, let look = model.removed() else { return }
        finish(.removed(look, pieceName: model.name(of: piece)))
    }

    /// See all: the picker is filled from what Swap already has, so it reads nothing.
    private func openSeeAll() {
        let picker = ClosetModel(scope: model.seeAllScope)
        picker.show(
            Array(model.setup.garments.values), suitcases: model.setup.suitcases,
            profile: Profile(preferences: Preferences(tracksLaundry: model.setup.situation.tracksLaundry)),
            now: model.setup.situation.date)
        seeAll = picker
    }
}
