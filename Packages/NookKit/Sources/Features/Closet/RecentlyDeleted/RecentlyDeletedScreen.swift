import DesignSystem
import Models
import SwiftUI

/// Recently deleted (LR-16): the pieces she deleted, each with the day it goes for good,
/// Restore, and Delete now (PRD §7.4, Phase 21a). Restoring shows a toast and the piece is back in
/// Closet. Delete now asks first, saying what goes with the piece, then deletes it for good.
struct RecentlyDeletedScreen: View {
    @Environment(\.services) private var services
    @State private var model = RecentlyDeletedModel()
    @State private var toast: NookToastMessage?

    var body: some View {
        RecentlyDeletedPage(model: model, retry: reload, restore: restore, deleteNow: askToDelete)
            .navigationTitle(
                Text("Recently deleted", bundle: .module, comment: "Screen title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .nookToast($toast)
            .alert(
                model.confirming.map { RecentlyDeletedText.confirmTitle($0.piece.name) } ?? "",
                isPresented: Binding(get: { model.confirming != nil }, set: { if !$0 { model.confirming = nil } }),
                presenting: model.confirming
            ) { preview in
                // No identifier: on an alert button it made XCUITest find the button twice.
                Button(RecentlyDeletedText.confirmButton, role: .destructive) { deletePermanently(preview) }
                Button(RecentlyDeletedText.cancel, role: .cancel) {}
            } message: { preview in
                Text(RecentlyDeletedText.confirmMessage(preview))
            }
            .task { await model.load(from: services) }
            // Recently deleted's quick tour (Stage A audit), once a deleted piece is listed.
            .screenTour(
                RecentlyDeletedTour.definition, isReady: model.phase == .loaded && !model.isEmpty && toast == nil)
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private func askToDelete(_ piece: Garment) {
        Task {
            do {
                try await model.askToDeletePermanently(piece.id, in: services)
            } catch {
                toast = RecentlyDeletedText.failedToast
            }
        }
    }

    private func deletePermanently(_ preview: PermanentDeletionPreview) {
        Task {
            do {
                guard let name = try await model.deletePermanently(preview, in: services) else { return }
                toast = NookToastMessage(RecentlyDeletedText.deletedToast(name), systemImage: "trash")
            } catch {
                toast = RecentlyDeletedText.failedToast
            }
        }
    }

    private func restore(_ piece: Garment) {
        let closet = services.closet
        Task {
            do {
                guard let restored = try await model.restore(piece.id, in: closet) else { return }
                toast = NookToastMessage(
                    String(
                        localized: "\(restored.name) is back in your closet", bundle: .module,
                        comment: "Toast after Restore, with the piece's name"),
                    systemImage: "checkmark")
            } catch {
                toast = RecentlyDeletedText.failedToast
            }
        }
    }
}

/// Recently deleted's content. Separate from the screen so snapshot tests can draw it.
struct RecentlyDeletedPage: View {
    let model: RecentlyDeletedModel
    var retry: () -> Void = {}
    var restore: (Garment) -> Void = { _ in }
    var deleteNow: (Garment) -> Void = { _ in }

    @Environment(\.closetIsStillImage) private var isStillImage

    var body: some View {
        if isStillImage {
            page.background(Color.nook.wallGradient)
        } else {
            TourScrollReader {
                ScrollView(.vertical) { page }
            }
            .background(Color.nook.wallGradient.ignoresSafeArea())
        }
    }

    private var page: some View {
        content
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.vertical, NookSpacing.large)
            .readablePane(maxWidth: GarmentDetailPage.maximumWidth)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(String(localized: "Opening Recently deleted", bundle: .module, comment: "Loading"))
                .padding(.top, NookSpacing.xxxLarge)
        case .failed:
            NookErrorState(
                String(
                    localized: "Recently deleted didn’t load", bundle: .module, comment: "Recently deleted error title"),
                message: String(
                    localized: "Nothing was lost. Try again in a moment.", bundle: .module,
                    comment: "Closet error message"),
                retry: retry
            )
            .padding(.top, NookSpacing.xxxLarge)
        case .loaded:
            if model.isEmpty {
                NookEmptyState(
                    String(localized: "Nothing here", bundle: .module, comment: "Recently deleted is empty"),
                    message: String(
                        localized: "Pieces you delete stay here for 30 days, so you can bring them back.",
                        bundle: .module, comment: "Recently deleted, empty"),
                    systemImage: "trash"
                )
                .padding(.top, NookSpacing.xxxLarge)
                .accessibilityIdentifier("recentlyDeleted.empty")
            } else {
                list
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            Text(
                "Deleted pieces stay here for 30 days. After that they’re deleted for good.", bundle: .module,
                comment: "Recently deleted: how long pieces stay"
            )
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            ForEach(model.pieces) { piece in
                RecentlyDeletedRow(
                    piece: piece, now: model.loadedAt, isRestoring: model.restoring == piece.id,
                    isDeleting: model.deleting == piece.id, isFirst: piece.id == model.pieces.first?.id,
                    restore: { restore(piece) }, deleteNow: { deleteNow(piece) })
            }
        }
    }
}

/// One deleted piece: its picture, name, the day it goes for good, Restore and Delete now.
private struct RecentlyDeletedRow: View {
    let piece: Garment
    let now: Date
    let isRestoring: Bool
    let isDeleting: Bool
    /// The first piece is the one the quick tour points at.
    let isFirst: Bool
    let restore: () -> Void
    let deleteNow: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var deadline: String {
        guard let purgeDate = piece.purgeDate else { return "" }
        let date = ShortDateText.format(purgeDate, now: now, calendar: calendar, locale: locale)
        return String(
            localized: "Kept until \(date)", bundle: .module,
            comment: "Recently deleted: the day a piece is deleted for good, such as Nov 13")
    }

    private var restoreLabel: String {
        String(localized: "Restore \(piece.name)", bundle: .module, comment: "Spoken on Restore, with the piece's name")
    }

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout =
            stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.small))
            : AnyLayout(HStackLayout(alignment: .center, spacing: NookSpacing.medium))
        layout {
            HStack(spacing: NookSpacing.medium) {
                GarmentPicture(piece, size: CGSize(width: 50, height: 64))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                    Text(piece.name)
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                    Text(deadline)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("recentlyDeleted.piece.\(piece.id.rawValue)")
            .tourAnchor(RecentlyDeletedTour.Anchor.piece, label: "\(piece.name), \(deadline)", isEnabled: isFirst)
            VStack(alignment: stacked ? .leading : .trailing, spacing: NookSpacing.xxSmall) {
                NookButton(
                    String(localized: "Restore", bundle: .module, comment: "Button: brings a deleted piece back"),
                    systemImage: "arrow.uturn.backward", kind: .pill, size: .small, isLoading: isRestoring,
                    fillsWidth: stacked, action: restore
                )
                .accessibilityLabel(Text(restoreLabel))
                .accessibilityIdentifier("recentlyDeleted.restore.\(piece.id.rawValue)")
                .tourAnchor(
                    RecentlyDeletedTour.Anchor.restore, label: restoreLabel, isEnabled: isFirst, action: restore)
                NookButton(
                    RecentlyDeletedText.deleteNow, kind: .text, size: .small, isLoading: isDeleting,
                    fillsWidth: stacked, action: deleteNow
                )
                .accessibilityLabel(Text(RecentlyDeletedText.deleteNowLabel(piece.name)))
                .accessibilityIdentifier("recentlyDeleted.deleteNow.\(piece.id.rawValue)")
            }
            .fixedSize(horizontal: !stacked, vertical: false)
        }
        .padding(NookSpacing.medium)
        .background(Color.nook.tint, in: NookRadius.shape(NookRadius.group))
    }
}

/// Recently deleted's words for Delete now and its toasts.
enum RecentlyDeletedText {
    static var deleteNow: String {
        String(
            localized: "Delete now", bundle: .module, comment: "Button: deletes a piece in Recently deleted for good")
    }

    static func deleteNowLabel(_ name: String) -> String {
        String(
            localized: "Delete \(name) now", bundle: .module,
            comment: "Spoken on Delete now in Recently deleted, with the piece's name")
    }

    static func confirmTitle(_ name: String) -> String {
        String(
            localized: "Delete \(name) for good?", bundle: .module,
            comment: "Recently deleted: asks before deleting a piece for good")
    }

    static var confirmButton: String {
        String(localized: "Delete for good", bundle: .module, comment: "Button: confirms deleting a piece for good")
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Button: closes without changing anything")
    }

    /// What goes with the piece, and what stays (PRD §7.4's preview), one sentence each.
    static func confirmMessage(_ preview: PermanentDeletionPreview) -> String {
        var lines: [String] = [
            preview.hasPhoto
                ? String(
                    localized: "Its photo and details are deleted from this iPhone. This can’t be undone.",
                    bundle: .module, comment: "Delete for good: what goes, for a piece with a photo")
                : String(
                    localized: "Its details are deleted from this iPhone. This can’t be undone.", bundle: .module,
                    comment: "Delete for good: what goes, for a piece with no photo")
        ]
        if preview.hasUnsavedEdit {
            lines.append(
                String(
                    localized: "Your unsaved changes to it go too.", bundle: .module,
                    comment: "Delete for good: its unsaved Edit draft goes too"))
        }
        if !preview.savedLooks.isEmpty {
            let names = preview.savedLooks.map { look in
                look.name
                    ?? String(localized: "A look with no name", bundle: .module, comment: "Saved look with no name")
            }
            .formatted(.list(type: .and))
            lines.append(
                String(
                    localized: "Saved looks that use it keep their other pieces: \(names).", bundle: .module,
                    comment: "Delete for good: the saved looks that use the piece, by name"))
        }
        if !preview.suitcases.isEmpty {
            let names = preview.suitcases.map(\.name).formatted(.list(type: .and))
            lines.append(
                String(
                    localized: "It comes out of \(names).", bundle: .module,
                    comment: "Delete for good: the suitcases the piece leaves, by name"))
        }
        if preview.pictureCount > 0 {
            lines.append(
                String(
                    localized: "Try-on pictures with it in stay until you delete them.", bundle: .module,
                    comment: "Delete for good: try-on pictures showing the piece are kept"))
        }
        return lines.joined(separator: "\n\n")
    }

    static func deletedToast(_ name: String) -> String {
        String(
            localized: "\(name) is deleted for good", bundle: .module,
            comment: "Toast after Delete now, with the piece's name")
    }

    static var failedToast: NookToastMessage {
        NookToastMessage(
            String(
                localized: "That didn’t save. Nothing changed.", bundle: .module,
                comment: "Toast when a change to a piece couldn't be saved"),
            systemImage: "exclamationmark.circle")
    }
}
