import DesignSystem
import Models
import SwiftUI

/// Make your own look (LR-08.3), pushed from a garment's Style with this ("Make my own look")
/// and from "+ Make your own" on Saved Looks. It works offline and sends nothing. Add a piece
/// and Change open her pieces in a sheet with Closet's search and filters.
struct LookBuilderScreen: View {
    @Environment(\.services) private var services
    @Environment(\.locale) private var locale
    @State private var model: LookBuilderModel
    @State private var picker: ClosetModel?
    @State private var toast: NookToastMessage?

    init(startingPieceID: Garment.ID? = nil) {
        _model = State(initialValue: LookBuilderModel(startingPieceID: startingPieceID))
    }

    var body: some View {
        LookBuilderPage(
            model: model,
            actions: LookBuilderActions(
                pick: openPicker,
                save: save,
                retry: { Task { await model.load(from: services) } }
            )
        )
        .navigationTitle(LookBuilderText.title)
        .navigationBarTitleDisplayMode(.inline)
        .nookSheet(item: $picker, title: { _ in LookBuilderText.pickerTitle }, detents: [.large]) { picker in
            PiecePicker(
                model: picker,
                lead: LookBuilderText.pickerLead,
                prompt: String(
                    localized: "Search these pieces", bundle: .module, comment: "Search prompt in a piece picker"),
                hint: LookBuilderText.pickerHint,
                emptyTitle: String(
                    localized: "No pieces to add yet", bundle: .module,
                    comment: "Make your own look: picker with nothing she can wear"),
                emptyMessage: String(
                    localized: "Pieces in the wash or away don’t show here. Add a piece in Closet to build a look.",
                    bundle: .module, comment: "Make your own look: empty picker")
            ) { id in
                model.add(id)
                self.picker = nil
            }
        }
        // The page runs under the floating tab bar, so the toast sits on a clear layer that keeps
        // to the safe area.
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task { await model.load(from: services) }
        // Make your own look's quick tour (Phase 16b), once her closet has loaded.
        .screenTour(LookBuilderTour.definition, isReady: model.phase == .loaded && picker == nil && toast == nil)
    }

    /// The picker is filled from what the screen already loaded.
    private func openPicker(_ kind: GarmentCategory?) {
        let picker = ClosetModel(scope: model.pickerScope())
        picker.show(
            Array(model.garments.values), suitcases: model.suitcases,
            profile: Profile(preferences: Preferences(tracksLaundry: model.tracksLaundry)), now: model.loadedAt)
        if let kind, picker.pieceKinds.contains(kind) { picker.showOnly(kind) }
        self.picker = picker
    }

    private func save() {
        let fallback =
            YourLooksText.colourName(of: model.pieces, locale: locale) ?? LookBuilderText.fallbackName
        Task {
            do {
                try await model.save(fallbackName: fallback)
                toast = NookToastMessage(LookBuilderText.savedToast, systemImage: "heart.fill")
            } catch {
                toast = NookToastMessage(LookBuilderText.saveFailed, systemImage: "exclamationmark.circle")
            }
        }
    }
}
