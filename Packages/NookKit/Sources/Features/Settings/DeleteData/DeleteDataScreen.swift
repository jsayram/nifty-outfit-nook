import DesignSystem
import Models
import SwiftUI

/// Delete my data (Phase 14b), from Profile and from Privacy and terms. Two steps: this screen
/// says exactly what goes, then a question asks once more before anything is deleted. See
/// `DeleteDataModel`.
struct DeleteDataScreen: View {
    @Environment(\.services) private var services
    @Environment(\.dataDeleted) private var dataDeleted
    @Environment(\.signIn) private var signIn
    @State private var model: DeleteDataModel
    @State private var isAsking = false
    @State private var showsManage = false

    /// - Parameter scope: `thisDevice` for Delete my data, `account` for Delete my account (24c).
    init(scope: DeletionScope = .thisDevice) {
        _model = State(initialValue: DeleteDataModel(scope: scope))
    }

    var body: some View {
        DeleteDataPage(
            model: model, delete: { isAsking = true }, done: { dataDeleted() },
            manageSubscription: { showsManage = true }
        )
        .nookManageSubscriptionsSheet(isPresented: $showsManage, groupID: model.subscriptionGroupID)
        .navigationTitle(DeleteDataText.screenTitle(model.scope))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is on the wall, as on Profile.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .alert(DeleteDataText.askTitle(model.scope), isPresented: $isAsking) {
            Button(DeleteDataText.askDelete(model.scope), role: .destructive) {
                Task { await delete() }
            }
            Button(DeleteDataText.askCancel, role: .cancel) {}
        } message: {
            Text(DeleteDataText.askMessage(model.scope))
        }
        .task { await model.load(from: services) }
        // Delete my data's quick tour (Stage A audit), once the counts are read. Not while it
        // asks or deletes, or after a deletion that didn't finish.
        .screenTour(DeleteDataTour.definition, isReady: model.counts != nil && model.phase == .ready && !isAsking)
    }

    private func delete() async {
        if await model.delete(in: services, signIn: signIn) {
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
    /// Delete my account, after a deletion the backend is still finishing: starts the app fresh.
    var done: () -> Void = {}
    /// 30a: Apple's Manage subscription sheet.
    var manageSubscription: () -> Void = {}

    var body: some View {
        SettingsPage(
            header: SettingsHeader(
                title: DeleteDataText.screenTitle(model.scope), lede: DeleteDataText.lede(model.scope))
        ) {
            switch model.phase {
            case .incomplete(let report):
                NookBanner(
                    DeleteDataText.incomplete(report), systemImage: "exclamationmark.triangle", tone: .warning
                )
                .accessibilityIdentifier("deleteData.incomplete")
            case .notStarted(let reason):
                NookBanner(DeleteDataText.notStarted(reason), systemImage: "exclamationmark.triangle", tone: .warning)
                    .accessibilityIdentifier("deleteData.notStarted")
            case .finished(let report):
                NookBanner(DeleteDataText.finished(report), systemImage: "checkmark.circle", tone: .warning)
                    .accessibilityIdentifier("deleteData.finished")
            case .ready, .deleting:
                EmptyView()
            }

            SettingsGroup(header: DeleteDataText.whatGoesHeader, identifier: "deleteData.parts") {
                ForEach(model.parts, id: \.self) { part in
                    SettingsInfoRow(
                        title: DeleteDataText.title(part), detail: DeleteDataText.detail(part),
                        value: model.counts.flatMap { DeleteDataText.count(part, in: $0) },
                        systemImage: DeleteDataText.systemImage(part))
                }
            }
            .tourAnchor(DeleteDataTour.Anchor.parts, label: DeleteDataText.whatGoesHeader)

            SettingsGroup(header: DeleteDataText.afterHeader) {
                if model.scope == .account {
                    SettingsNote(DeleteDataText.afterAccount)
                    // 30a: only while a subscription may still bill her.
                    if model.subscriptionMayRenew {
                        SettingsNote(DeleteDataText.subscriptionNote)
                            .accessibilityIdentifier("deleteData.subscriptionNote")
                        Button(action: manageSubscription) {
                            NookRow(
                                StylingAccessText.manage, subtitle: StylingAccessText.manageDetail,
                                systemImage: "creditcard", accessory: .chevron)
                        }
                        .buttonStyle(.nookRow)
                        .accessibilityIdentifier("deleteData.manageSubscription")
                    }
                    SettingsNote(DeleteDataText.providersNote)
                } else {
                    SettingsNote(DeleteDataText.after)
                    SettingsNote(DeleteDataText.nowhereElse)
                }
            }

            VStack(spacing: NookSpacing.small) {
                if model.phase.isFinished {
                    DoneButton(action: done)
                } else {
                    DeleteButton(
                        title: model.phase.isIncomplete
                            ? DeleteDataText.tryAgain : DeleteDataText.screenTitle(model.scope),
                        isDeleting: model.phase == .deleting, action: delete
                    )
                    // From the tour it asks once more, as the button does.
                    .tourAnchor(DeleteDataTour.Anchor.delete, label: SettingsText.deleteTitle, action: delete)
                }
                if !model.phase.isFinished {
                    Text(model.scope == .account ? DeleteDataText.cantUndoAccount : DeleteDataText.cantUndo)
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
}

extension DeleteDataModel.Phase {
    fileprivate var isIncomplete: Bool {
        if case .incomplete = self { return true }
        return false
    }

    fileprivate var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }
}

/// After Delete my account, when only the backend is still finishing: leaves for a fresh start.
private struct DoneButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(DeleteDataText.done)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: NookSpacing.minimumTapTarget)
        }
        .buttonStyle(.nook(.primary))
        .accessibilityIdentifier("deleteData.done")
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
        case .serverData:
            String(localized: "What the app’s server keeps", bundle: .module, comment: "Delete my account: a part")
        case .account: String(localized: "Your account", bundle: .module, comment: "Delete my account: a part")
        case .signInWithApple:
            String(localized: "Sign in with Apple", bundle: .module, comment: "Delete my account: a part")
        case .iCloudCopy:
            String(localized: "Your iCloud copy", bundle: .module, comment: "Delete my account: a part")
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
        case .serverData:
            String(
                localized:
                    "How much you’ve used the stylist and try-on, and sign-in records. Anything still running is stopped.",
                bundle: .module, comment: "Delete my account: under What the app’s server keeps")
        case .account:
            String(
                localized: "Your sign-in to the app, on every device", bundle: .module,
                comment: "Delete my account: under Your account")
        case .signInWithApple:
            String(
                localized: "The link between your Apple Account and this app", bundle: .module,
                comment: "Delete my account: under Sign in with Apple")
        case .iCloudCopy:
            String(
                localized: "The copy of your closet kept in your iCloud", bundle: .module,
                comment: "Delete my account: under Your iCloud copy")
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
        case .profile, .serverData, .account, .signInWithApple, .iCloudCopy: nil
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
        case .serverData: "server.rack"
        case .account: "person.crop.circle.badge.xmark"
        case .signInWithApple: "apple.logo"
        case .iCloudCopy: "icloud"
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

    static func askTitle(_ scope: DeletionScope) -> String {
        switch scope {
        case .thisDevice:
            String(localized: "Delete everything?", bundle: .module, comment: "Delete my data: the question's title")
        case .account:
            String(
                localized: "Delete your account?", bundle: .module, comment: "Delete my account: the question's title")
        }
    }

    static func askMessage(_ scope: DeletionScope) -> String {
        switch scope {
        case .thisDevice:
            String(
                localized:
                    "Your closet, looks, pictures, suitcases, profile and unsaved work will be deleted from this iPhone. This can’t be undone.",
                bundle: .module, comment: "Delete my data: the question")
        case .account:
            String(
                localized:
                    "Your account, everything the app’s server keeps for it, and everything in the app on this iPhone will be deleted. Apple will ask you to confirm it’s you. This can’t be undone.",
                bundle: .module, comment: "Delete my account: the question")
        }
    }

    static func askDelete(_ scope: DeletionScope) -> String {
        switch scope {
        case .thisDevice:
            String(localized: "Delete everything", bundle: .module, comment: "Delete my data: the question's button")
        case .account:
            String(localized: "Delete my account", bundle: .module, comment: "Delete my account: the question's button")
        }
    }

    // MARK: Delete my account (24c)

    static func screenTitle(_ scope: DeletionScope) -> String {
        switch scope {
        case .thisDevice: SettingsText.deleteTitle
        case .account: accountTitle
        }
    }

    static var accountTitle: String {
        String(
            localized: "Delete my account", bundle: .module, comment: "Delete my account: the screen's title and row")
    }

    static func lede(_ scope: DeletionScope) -> String {
        switch scope {
        case .thisDevice: SettingsText.deleteLede
        case .account:
            String(
                localized:
                    "Deletes your account and everything the app keeps for you, on the server and on this iPhone.",
                bundle: .module, comment: "Delete my account: under the title")
        }
    }

    static var afterAccount: String {
        String(
            localized:
                "You’re signed out and the app starts fresh, as if it were just installed. Signing in again later makes a new, empty account.",
            bundle: .module, comment: "Delete my account: what happens after")
    }

    /// App Store rules: deleting an account doesn't cancel an App Store subscription. Shown only
    /// while she has one that may renew, with Manage subscription under it (30a).
    static var subscriptionNote: String {
        String(
            localized:
                "Deleting your account doesn’t cancel your subscription. Cancel it with Manage subscription below, or in the Settings app: tap your name, then Subscriptions.",
            bundle: .module, comment: "Delete my account: the subscription note")
    }

    static var providersNote: String {
        String(
            localized:
                "Copies you exported stay where you saved them. Requests the stylist and try-on already sent are kept by those services for the time the privacy policy says, and then deleted.",
            bundle: .module, comment: "Delete my account: what deletion can't reach")
    }

    static var cantUndoAccount: String {
        String(
            localized: "You’ll be asked once more, then Apple asks you to confirm it’s you. Deleting can’t be undone.",
            bundle: .module, comment: "Delete my account: under the button")
    }

    static var done: String {
        String(
            localized: "Done", bundle: .module,
            comment: "Delete my account: leaves after a deletion the server is finishing")
    }

    static func notStarted(_ reason: DeletionNotStarted) -> String {
        switch reason {
        case .cancelled, .unavailable(nil):
            String(
                localized: "Nothing was deleted. The app’s server couldn’t take the request. Try again in a moment.",
                bundle: .module, comment: "Delete my account: didn't start, server problem")
        case .offline:
            String(
                localized: "Nothing was deleted. You’re offline: connect to the internet and try again.",
                bundle: .module, comment: "Delete my account: didn't start, offline")
        case .signedOut:
            String(
                localized: "Nothing was deleted. Sign in again, then try again.", bundle: .module,
                comment: "Delete my account: didn't start, signed out")
        case .unavailable(let seconds?):
            String(
                localized: "Nothing was deleted. The app’s server is busy. Try again in \(seconds) seconds.",
                bundle: .module, comment: "Delete my account: didn't start, try again after a wait")
        }
    }

    /// Everything on this iPhone is gone; says what the server is still doing, and what she can do
    /// about the Apple link if it couldn't be removed.
    static func finished(_ report: DeletionReport) -> String {
        var lines = [
            String(
                localized: "Everything on this iPhone is deleted and you’re signed out.", bundle: .module,
                comment: "Delete my account: finished on the iPhone")
        ]
        let pending = report.pendingParts
        if !pending.isEmpty {
            let names = pending.map(title).formatted(.list(type: .and))
            lines.append(
                String(
                    localized:
                        "Still being deleted on the server: \(names). It finishes on its own; you don’t need to do anything.",
                    bundle: .module, comment: "Delete my account: server parts still pending"))
        }
        if report.outcomes[.signInWithApple] == .failed {
            lines.append(
                String(
                    localized:
                        "The app couldn’t remove its Sign in with Apple link. To remove it, open the Settings app, tap your name, then Sign in with Apple.",
                    bundle: .module, comment: "Delete my account: the Apple link needs her"))
        }
        if report.outcomes[.iCloudCopy] == .pending {
            lines.append(
                String(
                    localized: "Your iCloud copy is deleted the next time this iPhone is online.", bundle: .module,
                    comment: "Delete my account: iCloud copy pending"))
        }
        return lines.joined(separator: " ")
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
