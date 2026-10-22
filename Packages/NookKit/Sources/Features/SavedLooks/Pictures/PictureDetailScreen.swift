import DesignSystem
import Models
import SwiftUI

/// Picture detail, pushed from the Pictures tab, a look's pictures, or Try it on's See the
/// picture (Phase 12b). It reads the picture each time it appears, so a look changed or deleted
/// meanwhile shows.
///
/// See the look and Delete picture are handed to Saved Looks, which owns the path and the toast:
/// it goes back to where she came from and offers Undo there (playbook, Phase 7a).
struct PictureDetailScreen: View {
    let seeLook: (Look) -> Void
    let deleted: (PictureRemoval) -> Void
    /// Shown beside the Pictures tab's grid on iPad (Phase 15b) rather than pushed: no bar of
    /// its own.
    var isBeside = false

    @Environment(\.services) private var services
    @State private var model: PictureDetailModel
    @State private var toast: NookToastMessage?
    /// 33a: "See what was sent", open.
    @State private var showsSent = false

    init(
        pictureID: TryOnPicture.ID, seeLook: @escaping (Look) -> Void, deleted: @escaping (PictureRemoval) -> Void,
        isBeside: Bool = false
    ) {
        self.seeLook = seeLook
        self.deleted = deleted
        self.isBeside = isBeside
        _model = State(initialValue: PictureDetailModel(pictureID: pictureID))
    }

    var body: some View {
        PictureDetailPage(
            model: model,
            actions: PictureDetailActions(
                seeLook: seeLook, delete: delete, retry: reload, seeWhatWasSent: { showsSent = true })
        )
        .nookSheet(isPresented: $showsSent, title: SentText.title, detents: [.large]) {
            if let sent = model.item?.picture.sent {
                SentImagesView(sent: sent, garments: model.garments)
            }
        }
        // The title is big on the page instead.
        .pagedTitle(TryOnText.pictureTitle, isPushed: !isBeside)
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task {
            await model.load(from: services)
            services.aiJobs.markPictureSeen(model.pictureID)
        }
        // A try-on picture's quick tour (Phase 16b), while its look is still saved to go back to.
        .screenTour(
            PictureTour.definition, isReady: model.phase == .loaded && model.item?.look != nil && toast == nil)
    }

    private func reload() {
        Task { await model.load(from: services) }
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
