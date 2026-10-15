import DesignSystem
import Models
import SwiftUI

/// Garment detail (Phase 7a): one piece, its facts, and what she can do with it.
///
/// Edit opens Edit piece (7b). Style with this asks whether to Style Me with it (10a) or make her
/// own look (a stand-in until 11). Each suitcase name opens that suitcase
/// (a stand-in until 13). Remove from closet asks first, then hands the removal back to Closet,
/// which goes back to the grid and offers Undo (LR-16.1).
struct GarmentDetailScreen: View {
    let garmentID: Garment.ID
    /// The name Closet showed, until the piece loads.
    let name: String
    let open: (ClosetDestination) -> Void
    let back: () -> Void
    let removed: (GarmentRemoval) -> Void

    @Environment(\.services) private var services
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var model: GarmentDetailModel
    @State private var showsStyleChoice = false
    @State private var pendingStyleChoice: StyleWithThisChoice?
    @State private var showsRemove = false
    @State private var pendingRemoval: GarmentRemoval?
    @State private var toast: NookToastMessage?

    init(
        garmentID: Garment.ID,
        name: String,
        open: @escaping (ClosetDestination) -> Void,
        back: @escaping () -> Void,
        removed: @escaping (GarmentRemoval) -> Void
    ) {
        self.garmentID = garmentID
        self.name = name
        self.open = open
        self.back = back
        self.removed = removed
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
                remove: { showsRemove = true }
            )
        )
        .navigationTitle(currentName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The name is the big title on the page instead.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
            if model.isInCloset {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        open(.editPiece(garmentID, name: currentName))
                    } label: {
                        // Words as well as the icon, as in the mockup.
                        HStack(spacing: NookSpacing.xSmall) {
                            Image(systemName: "pencil")
                            Text("Edit", bundle: .module, comment: "Button: edits a piece")
                        }
                        .padding(.horizontal, NookSpacing.xSmall)
                    }
                    .accessibilityIdentifier("garment.edit")
                }
            }
        }
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
        .nookToast($toast)
        .task { await model.load(from: services) }
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
