import DesignSystem
import Models
import SwiftUI

/// Look detail, pushed from Saved Looks (Phase 12a). It reads the look each time it appears, so
/// a piece changed on garment detail shows when she comes back.
///
/// Wear today, Swap a piece and Rename change the look here, each with a toast and Undo. Delete
/// look hands the removal back to Saved Looks, which goes back to the grid and offers Undo there
/// (playbook, Phase 7a). Try it on opens its sheet (Phase 12b); a new picture shows in the look's
/// pictures when the sheet closes. Find one opens a stand-in until Phase 34.
struct LookDetailScreen: View {
    /// Changes when another screen changed something the look shows, so it reads again.
    let changes: Int
    /// Opens one of the look's pieces.
    let openGarment: (Garment.ID, String) -> Void
    /// Opens one of the look's try-on pictures.
    let openPicture: (TryOnPicture.ID) -> Void
    let deleted: (SavedLookRemoval) -> Void
    /// Shown beside Saved Looks' grid on iPad (Phase 15b) rather than pushed: no bar of its own.
    var isBeside = false

    @Environment(\.services) private var services
    @State private var model: LookDetailModel
    @State private var swapping: SwapRoute?
    @State private var stub: ResultStub?
    @State private var renaming: RenameDraft?
    @State private var toast: NookToastMessage?
    @State private var tryingOn: TryOnRoute?

    init(
        lookID: Look.ID, changes: Int = 0, openGarment: @escaping (Garment.ID, String) -> Void,
        openPicture: @escaping (TryOnPicture.ID) -> Void = { _ in },
        deleted: @escaping (SavedLookRemoval) -> Void,
        isBeside: Bool = false
    ) {
        self.changes = changes
        self.openGarment = openGarment
        self.openPicture = openPicture
        self.deleted = deleted
        self.isBeside = isBeside
        _model = State(initialValue: LookDetailModel(lookID: lookID))
    }

    var body: some View {
        LookDetailPage(
            model: model,
            actions: LookDetailActions(
                wearToday: toggleWear,
                swap: { openSwap(at: nil) },
                swapIt: { piece in openSwap(at: LookPiece.ID(piece.id)) },
                tryOn: openTryOn,
                rename: { renaming = RenameDraft(text: model.name) },
                delete: delete,
                openPiece: { piece in
                    guard let id = model.look?.pieces.first(where: { $0.id.rawValue == piece.id })?.garmentID
                    else { return }
                    openGarment(id, piece.name)
                },
                findOne: { stub = .findOne(pieceName: $0.name) },
                retry: reload,
                openPicture: openPicture
            )
        )
        // The name is the big title on the page instead.
        .pagedTitle(model.name, isPushed: !isBeside)
        .navigationDestination(item: $swapping) { route in
            SwapScreen(model: route.model, finish: finishSwap)
        }
        .nookSheet(item: $stub, title: { $0.title }, subtitle: { $0.subtitle }) { stub in
            ResultStubContent(stub: stub)
        }
        .tryOnSheet($tryingOn, seePicture: { openPicture($0.id) })
        .onChange(of: tryingOn == nil) { _, closed in
            // A picture made in the sheet joins the look's pictures.
            if closed { reload() }
        }
        .nookSheet(item: $renaming, title: { _ in LookDetailText.renameTitle }) { draft in
            RenameLookSheet(draft: draft, problem: model.renameProblem) { name in
                await rename(to: name)
            }
        }
        // The page's scroll view runs under the floating tab bar, so the toast sits on a clear
        // layer that keeps to the safe area (playbook, Phase 10b).
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task(id: changes) { await model.load(from: services) }
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private func openTryOn() {
        tryingOn = model.tryOnModel().map { TryOnRoute(model: $0) }
    }

    // MARK: Wear today

    private func toggleWear() {
        let wasWorn = model.isWornToday
        Task {
            do {
                if wasWorn {
                    _ = try await model.removeTodaysWear()
                    toast = NookToastMessage(LookDetailText.wearRemovedToast, systemImage: "calendar")
                } else {
                    let wear = try await model.wearToday()
                    toast = NookToastMessage(
                        LookDetailText.wornTodayToast, systemImage: "checkmark.circle",
                        actionTitle: YourLooksText.undo
                    ) {
                        Task { try? await model.undo(wear) }
                    }
                }
            } catch {
                toast = NookToastMessage(LookDetailText.failedToast, systemImage: "exclamationmark.circle")
            }
        }
    }

    // MARK: Swap a piece

    private func openSwap(at pieceID: LookPiece.ID?) {
        guard let swap = model.swapModel(startingAt: pieceID) else { return }
        swapping = SwapRoute(model: swap)
    }

    /// Use this top or Remove this piece: back to the look, changed, with Undo (LR-08.2).
    private func finishSwap(_ outcome: SwapOutcome) {
        swapping = nil
        let changed: Look
        let message: String
        switch outcome {
        case .swapped(let look, let name):
            changed = look
            message = SwapText.swapped(name)
        case .removed(let look, let name):
            changed = look
            message = SwapText.removed(name)
        }
        Task {
            do {
                let before = try await model.applySwap(changed)
                toast = NookToastMessage(
                    message, systemImage: "arrow.left.arrow.right", actionTitle: YourLooksText.undo
                ) {
                    Task {
                        try? await model.restore(before)
                        toast = NookToastMessage(SwapText.undone, systemImage: "arrow.uturn.backward")
                    }
                }
            } catch {
                toast = NookToastMessage(LookDetailText.failedToast, systemImage: "exclamationmark.circle")
            }
        }
    }

    // MARK: Rename and delete

    /// Saves the name and closes the sheet. Returns false when it couldn't be saved.
    private func rename(to name: String) async -> Bool {
        do {
            try await model.rename(to: name)
            renaming = nil
            toast = NookToastMessage(LookDetailText.renamed, systemImage: "checkmark")
            return true
        } catch {
            return false
        }
    }

    private func delete() {
        Task {
            do {
                deleted(try await model.delete())
            } catch {
                toast = NookToastMessage(LookDetailText.failedToast, systemImage: "exclamationmark.circle")
            }
        }
    }
}

/// The name being typed in Rename look.
struct RenameDraft: Identifiable, Hashable {
    let id = UUID()
    var text: String
}
