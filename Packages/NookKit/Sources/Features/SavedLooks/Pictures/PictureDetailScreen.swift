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

    @Environment(\.services) private var services
    @State private var model: PictureDetailModel
    @State private var toast: NookToastMessage?

    init(
        pictureID: TryOnPicture.ID, seeLook: @escaping (Look) -> Void, deleted: @escaping (PictureRemoval) -> Void
    ) {
        self.seeLook = seeLook
        self.deleted = deleted
        _model = State(initialValue: PictureDetailModel(pictureID: pictureID))
    }

    var body: some View {
        PictureDetailPage(
            model: model,
            actions: PictureDetailActions(seeLook: seeLook, delete: delete, retry: reload)
        )
        .navigationTitle(TryOnText.pictureTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is big on the page instead.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task { await model.load(from: services) }
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
