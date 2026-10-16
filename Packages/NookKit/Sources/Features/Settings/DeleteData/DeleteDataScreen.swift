import DesignSystem
import Models
import SwiftUI

/// Delete my data (Phase 14b), from Profile and from Privacy and terms. Two steps: this screen
/// says exactly what goes, then a question asks once more before anything is deleted. See
/// `DeleteDataModel`.
struct DeleteDataScreen: View {
    @Environment(\.services) private var services
    @Environment(\.dataDeleted) private var dataDeleted
    @State private var model = DeleteDataModel()
    @State private var isAsking = false

    var body: some View {
        DeleteDataPage(model: model, delete: { isAsking = true })
            .navigationTitle(SettingsText.deleteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The title is on the wall, as on Profile.
                ToolbarItem(placement: .principal) {
                    Text(verbatim: "").accessibilityHidden(true)
                }
            }
            .alert(DeleteDataText.askTitle, isPresented: $isAsking) {
                Button(DeleteDataText.askDelete, role: .destructive) {
                    Task { await delete() }
                }
                Button(DeleteDataText.askCancel, role: .cancel) {}
            } message: {
                Text(DeleteDataText.askMessage)
            }
            .task { await model.load(from: services) }
    }

    private func delete() async {
        if await model.delete(in: services) {
            // Everything is gone: every tab is built again, on Home.
            dataDeleted()
        }
    }
}

/// Delete my data, top to bottom: what goes, what happens after, and the button. Separate from
/// `DeleteDataScreen` so snapshot tests can draw it.
struct DeleteDataPage: View {
    let model: DeleteDataModel
    var delete: () -> Void = {}

    var body: some View {
        SettingsPage(header: SettingsHeader(title: SettingsText.deleteTitle, lede: SettingsText.deleteLede)) {
            if case .incomplete(let report) = model.phase {
                NookBanner(
                    DeleteDataText.incomplete(report), systemImage: "exclamationmark.triangle", tone: .warning
                )
                .accessibilityIdentifier("deleteData.incomplete")
            }

            SettingsGroup(header: DeleteDataText.whatGoesHeader, identifier: "deleteData.parts") {
                ForEach(model.parts, id: \.self) { part in
                    SettingsInfoRow(
                        title: DeleteDataText.title(part), detail: DeleteDataText.detail(part),
                        value: model.counts.flatMap { DeleteDataText.count(part, in: $0) },
                        systemImage: DeleteDataText.systemImage(part))
                }
            }

            SettingsGroup(header: DeleteDataText.afterHeader) {
                SettingsNote(DeleteDataText.after)
                SettingsNote(DeleteDataText.nowhereElse)
            }

            VStack(spacing: NookSpacing.small) {
                DeleteButton(
                    title: model.phase.isIncomplete ? DeleteDataText.tryAgain : SettingsText.deleteTitle,
                    isDeleting: model.phase == .deleting, action: delete)
                Text(DeleteDataText.cantUndo)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NookSpacing.xSmall)
                    .floorCard()
            }
        }
    }
}

extension DeleteDataModel.Phase {
    fileprivate var isIncomplete: Bool {
        if case .incomplete = self { return true }
        return false
    }
}

/// The one button that deletes: solid in the error colour, with a trash icon and words, so it
/// never relies on colour alone. While deleting it shows the loading dots and ignores taps.
private struct DeleteButton: View {
    let title: String
    let isDeleting: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .callout) private var height: CGFloat = 50

    var body: some View {
        Button {
            if !isDeleting { action() }
        } label: {
            HStack(spacing: NookSpacing.small) {
                if isDeleting {
                    NookLoadingIndicator(size: .small)
                } else {
                    Image(systemName: "trash")
                        .accessibilityHidden(true)
                }
                Text(title)
                    .nookTextStyle(.button)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.nook.onAccent)
            .padding(.horizontal, NookSpacing.large)
            .padding(.vertical, NookSpacing.small)
            .frame(maxWidth: .infinity, minHeight: max(height, NookSpacing.minimumTapTarget))
            .background {
                NookRadius.shape(NookRadius.button)
                    .fill(Color.nook.error)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.button))
            }
            .contentShape(NookRadius.shape(NookRadius.button))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isDeleting ? Text(DeleteDataText.deleting) : Text(""))
        .accessibilityIdentifier("deleteData.delete")
    }
}

/// The words on Delete my data.
nonisolated enum DeleteDataText {
    static var whatGoesHeader: String {
        String(localized: "What’s deleted", bundle: .module, comment: "Delete my data: section header")
    }

    static func title(_ part: DataPart) -> String {
        switch part {
        case .closet: String(localized: "Your closet", bundle: .module, comment: "Delete my data: a part")
        case .looks: String(localized: "Looks", bundle: .module, comment: "Delete my data: a part")
        case .pictures: String(localized: "Try-on pictures", bundle: .module, comment: "Delete my data: a part")
        case .suitcases: String(localized: "Suitcases", bundle: .module, comment: "Delete my data: a part")
        case .profile: String(localized: "Your profile", bundle: .module, comment: "Delete my data: a part")
        case .drafts: String(localized: "Unsaved work", bundle: .module, comment: "Delete my data: a part")
        }
    }

    static func detail(_ part: DataPart) -> String? {
        switch part {
        case .closet:
            String(
                localized: "Every piece, with its pictures and details, and Recently deleted", bundle: .module,
                comment: "Delete my data: under Your closet")
        case .looks:
            String(
                localized: "Saved looks, looks you made, and earlier results", bundle: .module,
                comment: "Delete my data: under Looks")
        case .pictures, .suitcases: nil
        case .profile:
            String(
                localized:
                    "Name on your sign, Preferences, fit, measurements, try-on photo, the app tours you’ve seen and the closet you started with",
                bundle: .module,
                comment: "Delete my data: under Your profile (tours since Phase 16b, the starting closet since 17)")
        case .drafts:
            String(
                localized: "Pieces and looks you started but didn’t save", bundle: .module,
                comment: "Delete my data: under Unsaved work")
        }
    }

    /// "21 pieces", or `nil` for the profile, which isn't counted.
    static func count(_ part: DataPart, in counts: DeleteDataModel.Counts) -> String? {
        switch part {
        case .closet:
            String(
                localized: "\(counts.pieces) pieces", bundle: .module,
                comment: "Source plate: how many pieces the source has")
        case .looks:
            String(
                localized: "\(counts.looks) looks", bundle: .module, comment: "Saved Looks: how many looks she saved")
        case .pictures:
            String(localized: "\(counts.pictures) pictures", bundle: .module, comment: "How many try-on pictures")
        case .suitcases:
            String(
                localized: "\(counts.suitcases) suitcases", bundle: .module,
                comment: "Closet tile: how many suitcases she has")
        case .profile: nil
        case .drafts:
            counts.drafts == 0
                ? String(localized: "None", bundle: .module, comment: "Delete my data: no unsaved work")
                : String(
                    localized: "\(counts.drafts) drafts", bundle: .module,
                    comment: "Delete my data: how many unsaved drafts")
        }
    }

    static func systemImage(_ part: DataPart) -> String {
        switch part {
        case .closet: "hanger"
        case .looks: "bookmark"
        case .pictures: "camera"
        case .suitcases: "suitcase"
        case .profile: "person.crop.circle"
        case .drafts: "square.and.pencil"
        }
    }

    static var afterHeader: String {
        String(localized: "Afterwards", bundle: .module, comment: "Delete my data: section header")
    }

    static var after: String {
        String(
            localized:
                "The app starts fresh, as if it were just installed. It opens on the welcome, and you choose a starting closet again.",
            bundle: .module, comment: "Delete my data: what happens after")
    }

    static var nowhereElse: String {
        String(
            localized:
                "Nothing about you is kept anywhere else. This test build has no account and sends nothing.",
            bundle: .module, comment: "Delete my data: nothing is held off the iPhone in Stage A")
    }

    static var cantUndo: String {
        String(
            localized: "You’ll be asked once more. Deleting can’t be undone.", bundle: .module,
            comment: "Delete my data: under the button")
    }

    static var tryAgain: String {
        String(localized: "Try again", bundle: .module, comment: "Delete my data: the button after a failure")
    }

    static var deleting: String {
        String(localized: "Deleting", bundle: .module, comment: "VoiceOver value while data is being deleted")
    }

    // MARK: The question

    static var askTitle: String {
        String(localized: "Delete everything?", bundle: .module, comment: "Delete my data: the question's title")
    }

    static var askMessage: String {
        String(
            localized:
                "Your closet, looks, pictures, suitcases, profile and unsaved work will be deleted from this iPhone. This can’t be undone.",
            bundle: .module, comment: "Delete my data: the question")
    }

    static var askDelete: String {
        String(localized: "Delete everything", bundle: .module, comment: "Delete my data: the question's button")
    }

    static var askCancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Button: closes without changing anything")
    }

    // MARK: Afterwards

    /// What's left after a deletion that didn't finish, part by part.
    static func incomplete(_ report: DeletionReport) -> String {
        let left = report.failedParts + report.pendingParts
        if left.count == report.order.count {
            return String(
                localized: "Nothing was deleted. Try again in a moment.", bundle: .module,
                comment: "Delete my data: every part failed")
        }
        let names = left.map(title).formatted(.list(type: .and))
        return String(
            localized: "Most of your data is deleted, but not: \(names). Try again to finish.", bundle: .module,
            comment: "Delete my data: some parts failed, with their names")
    }
}
