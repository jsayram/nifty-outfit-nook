import DesignSystem
import Models
import SwiftUI

/// Recently deleted (LR-16): the pieces she deleted, each with the day it goes for good and
/// Restore. Restoring shows a toast and the piece is back in Closet.
struct RecentlyDeletedScreen: View {
    @Environment(\.services) private var services
    @State private var model = RecentlyDeletedModel()
    @State private var toast: NookToastMessage?

    var body: some View {
        RecentlyDeletedPage(model: model, retry: reload, restore: restore)
            .navigationTitle(
                Text("Recently deleted", bundle: .module, comment: "Screen title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .nookToast($toast)
            .task { await model.load(from: services) }
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private func restore(_ piece: Garment) {
        guard let closet = services?.closet else { return }
        Task {
            do {
                guard let restored = try await model.restore(piece.id, in: closet) else { return }
                toast = NookToastMessage(
                    String(
                        localized: "\(restored.name) is back in your closet", bundle: .module,
                        comment: "Toast after Restore, with the piece's name"),
                    systemImage: "checkmark")
            } catch {
                toast = NookToastMessage(
                    String(
                        localized: "That didn’t save. Nothing changed.", bundle: .module,
                        comment: "Toast when a change to a piece couldn't be saved"),
                    systemImage: "exclamationmark.circle")
            }
        }
    }
}

/// Recently deleted's content. Separate from the screen so snapshot tests can draw it.
struct RecentlyDeletedPage: View {
    let model: RecentlyDeletedModel
    var retry: () -> Void = {}
    var restore: (Garment) -> Void = { _ in }

    @Environment(\.closetIsStillImage) private var isStillImage

    var body: some View {
        if isStillImage {
            page.background(Color.nook.wallGradient)
        } else {
            ScrollView(.vertical) { page }
                .background(Color.nook.wallGradient.ignoresSafeArea())
        }
    }

    private var page: some View {
        content
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.vertical, NookSpacing.large)
            .frame(maxWidth: GarmentDetailPage.maximumWidth)
            .frame(maxWidth: .infinity)
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
                    piece: piece, now: model.loadedAt, isRestoring: model.restoring == piece.id
                ) {
                    restore(piece)
                }
            }
        }
    }
}

/// One deleted piece: its picture, name, the day it goes for good, and Restore.
private struct RecentlyDeletedRow: View {
    let piece: Garment
    let now: Date
    let isRestoring: Bool
    let restore: () -> Void

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
            NookButton(
                String(localized: "Restore", bundle: .module, comment: "Button: brings a deleted piece back"),
                systemImage: "arrow.uturn.backward", kind: .pill, size: .small, isLoading: isRestoring,
                fillsWidth: stacked, action: restore
            )
            .accessibilityLabel(
                Text("Restore \(piece.name)", bundle: .module, comment: "Spoken on Restore, with the piece's name")
            )
            .accessibilityIdentifier("recentlyDeleted.restore.\(piece.id.rawValue)")
        }
        .padding(NookSpacing.medium)
        .background(Color.nook.tint, in: NookRadius.shape(NookRadius.group))
    }
}
