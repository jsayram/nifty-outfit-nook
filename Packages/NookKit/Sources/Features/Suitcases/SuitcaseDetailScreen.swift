import DesignSystem
import Models
import SwiftUI

/// One suitcase (Phase 13, `suitcase.html`, PRD §7.7), pushed from Suitcases, a suitcase name on
/// garment detail (LR-11.4), or Style Me's "Add pieces" for an empty suitcase.
///
/// Packing happens on a sheet with Closet's search and filters. Each piece opens its detail, and
/// its minus takes it out, with Undo. "Style me from this suitcase" opens Style Me with it as the
/// source. The menu has Name and picture, Archive and Delete suitcase; Delete goes back to where
/// she came from, which offers Undo (`deleted`).
struct SuitcaseDetailScreen: View {
    let suitcaseID: Suitcase.ID
    /// The name the opening screen showed, until the suitcase loads.
    let name: String
    /// Opens the packing sheet as soon as it loads, as after "+ Add a suitcase".
    var startsPacking = false
    let open: (ClosetDestination) -> Void
    let back: () -> Void
    /// Delete suitcase: the opening screen goes back and offers Undo.
    let deleted: (SuitcaseChange) -> Void

    @Environment(\.services) private var services
    @State private var model: SuitcaseDetailModel
    @State private var packingList: ClosetModel?
    @State private var showsEditor = false
    @State private var toast: NookToastMessage?
    @State private var askedToPack = false

    init(
        suitcaseID: Suitcase.ID, name: String, startsPacking: Bool = false,
        open: @escaping (ClosetDestination) -> Void, back: @escaping () -> Void,
        deleted: @escaping (SuitcaseChange) -> Void
    ) {
        self.suitcaseID = suitcaseID
        self.name = name
        self.startsPacking = startsPacking
        self.open = open
        self.back = back
        self.deleted = deleted
        _model = State(initialValue: SuitcaseDetailModel(suitcaseID: suitcaseID))
    }

    private var currentName: String { model.suitcase?.name ?? name }

    var body: some View {
        SuitcaseDetailPage(
            model: model,
            actions: SuitcaseDetailActions(
                retry: reload,
                back: back,
                edit: { showsEditor = true },
                pack: openPacking,
                useForStyleMe: { setSource(.suitcase(suitcaseID)) },
                useMainCloset: { setSource(.mainCloset) },
                styleMe: { open(.styleMeFrom(.suitcase(suitcaseID))) },
                bringBack: { setArchived(false) },
                openPiece: { open(.garment($0.id, name: $0.name)) },
                removePiece: remove
            )
        )
        .navigationTitle(currentName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The name is the big title on the wall instead.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
            if model.phase == .loaded {
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
        }
        .nookSheet(
            item: $packingList,
            title: { _ in
                String(
                    localized: "Pack \(currentName)", bundle: .module,
                    comment: "Packing sheet title, with the suitcase's name")
            },
            detents: [.large],
            onDismiss: reload
        ) { list in
            PackingSheet(model: model, list: list, toggle: togglePacked)
        }
        .nookSheet(
            isPresented: $showsEditor,
            title: String(localized: "Name and picture", bundle: .module, comment: "Sheet title: edit a suitcase"),
            detents: [.large]
        ) {
            SuitcaseEditor(
                purpose: .edit, name: currentName, icon: model.suitcase?.icon ?? .rolling,
                problem: { model.nameProblem($0) }
            ) { newName, icon in
                do {
                    try await model.edit(name: newName, icon: icon, in: services)
                    showsEditor = false
                    return true
                } catch {
                    return false
                }
            }
        }
        // The page's scroll view runs under the floating tab bar, so the toast sits on a clear
        // layer that keeps to the safe area and stays above it.
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task {
            await model.load(from: services)
            if startsPacking, !askedToPack, model.phase == .loaded {
                askedToPack = true
                openPacking()
            }
        }
        // A suitcase's quick tour (Phase 16b), unless it's archived or a sheet is open. A new
        // suitcase opens on its packing sheet, so the tour waits until that closes.
        .screenTour(
            SuitcaseTour.definition(hasPieces: model.pieceCount > 0),
            isReady: model.phase == .loaded && !model.isArchived && packingList == nil && !showsEditor
                && toast == nil && (!startsPacking || askedToPack))
    }

    private var menu: some View {
        Menu {
            Button {
                showsEditor = true
            } label: {
                Label {
                    Text(
                        "Name and picture", bundle: .module,
                        comment: "Button: renames a suitcase or changes its picture")
                } icon: {
                    Image(systemName: "pencil")
                }
            }
            Button {
                setArchived(!model.isArchived)
            } label: {
                if model.isArchived {
                    Label {
                        Text("Bring it back", bundle: .module, comment: "Button: unarchives a suitcase")
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                } else {
                    Label {
                        Text("Archive suitcase", bundle: .module, comment: "Button: archives a suitcase")
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                }
            }
            Button(role: .destructive, action: delete) {
                Label {
                    Text("Delete suitcase", bundle: .module, comment: "Button: deletes a suitcase, not its pieces")
                } icon: {
                    Image(systemName: "trash")
                }
            }
            .accessibilityIdentifier("suitcase.delete")
        } label: {
            Label {
                Text("More", bundle: .module, comment: "Button: opens a suitcase's menu")
            } icon: {
                Image(systemName: "ellipsis")
            }
        }
        .accessibilityIdentifier("suitcase.menu")
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private func openPacking() {
        packingList = model.packingList()
    }

    private func togglePacked(_ id: Garment.ID) {
        Task {
            do {
                try await model.togglePacked(id, in: services)
                // The tiny suitcase on each piece and what VoiceOver reads follow at once.
                if let packingList { model.refresh(packingList) }
            } catch {
                toast = NookToastMessage(SuitcasesText.failed, systemImage: "exclamationmark.circle")
            }
        }
    }

    /// The minus on a piece: out of this suitcase only, with Undo.
    private func remove(_ item: ClosetItem) {
        Task {
            do {
                try await model.remove(item.id, in: services)
                toast = NookToastMessage(
                    String(
                        localized: "Removed \(item.name). It’s still in your closet.", bundle: .module,
                        comment: "Toast after taking a piece out of a suitcase"),
                    systemImage: "checkmark", actionTitle: SuitcasesText.undo
                ) {
                    Task { try? await model.putBack(item.id, in: services) }
                }
            } catch {
                toast = NookToastMessage(SuitcasesText.failed, systemImage: "exclamationmark.circle")
            }
        }
    }

    private func setSource(_ source: WardrobeSource) {
        Task {
            do {
                guard let previous = try await model.setSource(source, in: services) else { return }
                let name = source.isSuitcase ? currentName : SuitcasesText.mainCloset
                toast = NookToastMessage(
                    SuitcasesText.nowUsing(name), systemImage: "checkmark", actionTitle: SuitcasesText.undo
                ) {
                    Task { _ = try? await model.setSource(previous, in: services) }
                }
            } catch {
                toast = NookToastMessage(SuitcasesText.failed, systemImage: "exclamationmark.circle")
            }
        }
    }

    private func setArchived(_ archived: Bool) {
        Task {
            do {
                guard let change = try await model.setArchived(archived, in: services) else { return }
                toast = NookToastMessage(change.message, systemImage: "checkmark", actionTitle: SuitcasesText.undo) {
                    Task {
                        guard let services else { return }
                        try? await change.undo(in: services)
                        await model.load(from: services)
                    }
                }
            } catch {
                toast = NookToastMessage(SuitcasesText.failed, systemImage: "exclamationmark.circle")
            }
        }
    }

    /// Delete suitcase: no question first, since Undo puts back the same suitcase (as Delete
    /// look does, Phase 12a).
    private func delete() {
        Task {
            do {
                guard let change = try await model.delete(in: services) else { return }
                deleted(change)
            } catch {
                toast = NookToastMessage(SuitcasesText.failed, systemImage: "exclamationmark.circle")
            }
        }
    }
}
