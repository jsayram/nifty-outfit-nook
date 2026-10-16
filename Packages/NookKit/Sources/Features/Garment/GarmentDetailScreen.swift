import DesignSystem
import Models
import SwiftUI

/// Garment detail (Phase 7a): one piece, its facts, and what she can do with it.
///
/// Edit opens Edit piece (7b). Style with this asks whether to Style Me with it (10a) or make her
/// own look (11). Each suitcase name opens that suitcase, and Add to a suitcase packs it (13). Remove from closet asks first, then hands the removal back to Closet,
/// which goes back to the grid and offers Undo (LR-16.1).
struct GarmentDetailScreen: View {
    let garmentID: Garment.ID
    /// The name Closet showed, until the piece loads.
    let name: String
    let open: (ClosetDestination) -> Void
    let back: () -> Void
    let removed: (GarmentRemoval) -> Void
    /// Shown beside Closet's grid on iPad (Phase 15a) rather than pushed: no title or bar of its
    /// own, and Edit sits on the page.
    var isBeside = false

    @Environment(\.services) private var services
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var model: GarmentDetailModel
    @State private var showsStyleChoice = false
    @State private var pendingStyleChoice: StyleWithThisChoice?
    @State private var showsRemove = false
    @State private var showsSuitcases = false
    @State private var pendingRemoval: GarmentRemoval?
    @State private var toast: NookToastMessage?

    init(
        garmentID: Garment.ID,
        name: String,
        open: @escaping (ClosetDestination) -> Void,
        back: @escaping () -> Void,
        removed: @escaping (GarmentRemoval) -> Void,
        isBeside: Bool = false
    ) {
        self.garmentID = garmentID
        self.name = name
        self.open = open
        self.back = back
        self.removed = removed
        self.isBeside = isBeside
        _model = State(initialValue: GarmentDetailModel(garmentID: garmentID))
    }

    private var currentName: String { model.garment?.name ?? name }

    var body: some View {
        GarmentDetailPage(
            model: model,
            actions: GarmentDetailActions(
                retry: reload,
                back: back,
                openSuitcase: { open(.suitcase($0.id, name: $0.name)) },
                styleWithThis: { showsStyleChoice = true },
                toggleLaundry: toggleLaundry,
                addToSuitcase: { showsSuitcases = true },
                remove: { showsRemove = true },
                edit: pageEdit
            )
        )
        .modifier(DetailBar(isPushed: !isBeside, title: currentName, showsEdit: model.isInCloset, edit: openEditor))
        .nookSheet(
            isPresented: $showsStyleChoice,
            title: String(localized: "Style with this", bundle: .module, comment: "Sheet title"),
            subtitle: currentName,
            onDismiss: openPendingStyleChoice
        ) {
            StyleWithThisChoices { choice in
                pendingStyleChoice = choice
                showsStyleChoice = false
            }
        }
        .nookSheet(
            isPresented: $showsSuitcases,
            title: String(
                localized: "Add to a suitcase", bundle: .module, comment: "Button on garment detail (Phase 13)"),
            subtitle: String(
                localized: "The piece stays in your closet. A suitcase only lists it, no copy is made.",
                bundle: .module, comment: "Under the Add to a suitcase sheet's title")
        ) {
            AddToSuitcaseSheet(model: model, toggle: toggleSuitcase) {
                showsSuitcases = false
                open(.suitcases)
            }
        }
        .nookSheet(
            isPresented: $showsRemove,
            title: String(localized: "Remove from closet", bundle: .module, comment: "Sheet title (LR-16)"),
            subtitle: currentName,
            onDismiss: finishRemoval
        ) {
            RemoveFromClosetChoices(
                name: currentName,
                deadline: model.text(calendar: calendar, locale: locale)?.deletionDeadline ?? "",
                savedLookNames: model.savedLookNames,
                isSaving: model.isSaving,
                confirmNoLongerOwned: { remove(deleting: false) },
                confirmDelete: { remove(deleting: true) }
            )
        }
        // The page's scroll view runs under the floating tab bar, so the toast sits on a clear
        // layer that keeps to the safe area and stays above the tab bar (as on Your looks).
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task { await model.load(from: services) }
        // The piece's quick tour (Phase 16b), once it has loaded with its buttons: a piece she no
        // longer owns has none.
        .screenTour(
            GarmentTour.definition,
            isReady: model.phase == .loaded && model.isInCloset && !showsStyleChoice && !showsRemove
                && !showsSuitcases && toast == nil)
    }

    /// Edit on the page, only beside the grid.
    private var pageEdit: (() -> Void)? {
        guard isBeside else { return nil }
        return { openEditor() }
    }

    private func openEditor() {
        open(.editPiece(garmentID, name: currentName))
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private func openPendingStyleChoice() {
        guard let choice = pendingStyleChoice else { return }
        pendingStyleChoice = nil
        switch choice {
        case .styleMe: open(.styleMe(startingWith: garmentID, name: currentName))
        case .makeYourOwnLook: open(.makeYourOwnLook(startingWith: garmentID, name: currentName))
        }
    }

    /// Mark as dirty or Mark as clean, with Undo (RD-11).
    private func toggleLaundry() {
        guard let closet = services?.closet, let laundry = model.garment?.laundry else { return }
        let next: LaundryState = laundry == .dirty ? .clean : .dirty
        Task {
            do {
                guard let previous = try await model.setLaundry(next, in: closet) else { return }
                toast = NookToastMessage(
                    next == .dirty
                        ? String(localized: "Marked as dirty", bundle: .module, comment: "Toast after Mark as dirty")
                        : String(localized: "Marked clean", bundle: .module, comment: "Toast after Mark as clean"),
                    systemImage: "checkmark",
                    actionTitle: String(localized: "Undo", bundle: .module, comment: "Toast action")
                ) {
                    Task { try? await model.setLaundry(previous, in: closet) }
                }
            } catch {
                toast = Self.failureToast
            }
        }
    }

    /// Packs it in a suitcase or takes it out, from Add to a suitcase (Phase 13).
    private func toggleSuitcase(_ suitcase: Suitcase) {
        Task {
            do {
                try await model.toggleSuitcase(suitcase.id, in: services)
            } catch {
                showsSuitcases = false
                toast = Self.failureToast
            }
        }
    }

    /// "Yes, I don't have it" or "Delete it": saves, closes the sheet, then Closet takes over.
    private func remove(deleting: Bool) {
        guard let closet = services?.closet else { return }
        Task {
            do {
                let removal =
                    deleting
                    ? try await model.delete(in: closet, at: .now)
                    : try await model.markNoLongerOwned(in: closet)
                guard let removal else { return }
                pendingRemoval = removal
                showsRemove = false
            } catch {
                showsRemove = false
                toast = Self.failureToast
            }
        }
    }

    private func finishRemoval() {
        guard let removal = pendingRemoval else { return }
        pendingRemoval = nil
        removed(removal)
    }

    private static var failureToast: NookToastMessage {
        NookToastMessage(
            String(
                localized: "That didn’t save. Nothing changed.", bundle: .module,
                comment: "Toast when a change to a piece couldn't be saved"),
            systemImage: "exclamationmark.circle")
    }
}

/// A pushed detail's bar: the title (hidden, since the name is the page's big title) and Edit.
/// Beside Closet's grid there's no bar, and Edit is on the page.
private struct DetailBar: ViewModifier {
    let isPushed: Bool
    let title: String
    let showsEdit: Bool
    let edit: () -> Void

    func body(content: Content) -> some View {
        if isPushed {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // The name is the big title on the page instead.
                    ToolbarItem(placement: .principal) {
                        Text(verbatim: "").accessibilityHidden(true)
                    }
                    if showsEdit {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: edit) {
                                // Words as well as the icon, as in the mockup.
                                HStack(spacing: NookSpacing.xSmall) {
                                    Image(systemName: "pencil")
                                    Text("Edit", bundle: .module, comment: "Button: edits a piece")
                                }
                                .padding(.horizontal, NookSpacing.xSmall)
                            }
                            .accessibilityIdentifier("garment.edit")
                            .tourAnchor(GarmentTour.Anchor.edit, label: GarmentTourText.edit, action: edit)
                        }
                    }
                }
        } else {
            content
        }
    }
}

/// What VoiceOver calls garment detail's controls in its tour.
enum GarmentTourText {
    static var edit: String { String(localized: "Edit", bundle: .module, comment: "Button: edits a piece") }
}
