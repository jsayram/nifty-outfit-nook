import DesignSystem
import Models
import Observation
import SwiftUI

/// The iCloud screen (Phase 21b, decision 0004 §5), on Profile and Privacy and terms. It appears
/// only in a build with iCloud on (`NookServices.iCloud`; docs/icloud.md has the switch).
///
/// The switch asks before it turns sync on, with what it means and the space it takes, and asks
/// how to turn it off. The status never says everything is in iCloud while anything waits (PRD
/// 15.1). When iCloud changed under the app (signed out, another account, the copy deleted in
/// Settings or on another device), the question and her choices come first.
@MainActor
@Observable
final class ICloudModel {
    private(set) var status: ICloudSyncStatus?
    /// Why turning on didn't work, once.
    private(set) var problem: String?
    private(set) var isBusy = false
    var isAskingTurnOn = false
    var isAskingTurnOff = false

    func load(_ service: (any ICloudSyncService)?) async {
        status = await service?.status()
    }

    func set(_ isOn: Bool) {
        problem = nil
        if isOn { isAskingTurnOn = true } else { isAskingTurnOff = true }
    }

    func turnOn(_ service: (any ICloudSyncService)?) async {
        guard let service else { return }
        await run(service) { problem = ICloudText.turnOnProblem(await service.turnOn()) }
    }

    func turnOff(_ service: (any ICloudSyncService)?, deletingCopy: Bool) async {
        guard let service else { return }
        await run(service) { _ = await service.turnOff(deletingCopy: deletingCopy) }
    }

    func answer(_ choice: ICloudChoice, _ service: (any ICloudSyncService)?) async {
        guard let service else { return }
        await run(service) { await service.answer(choice) }
    }

    func tryAgain(_ service: (any ICloudSyncService)?) async {
        guard let service else { return }
        await run(service) { await service.syncNow() }
    }

    private func run(_ service: any ICloudSyncService, _ work: () async -> Void) async {
        isBusy = true
        await work()
        status = await service.status()
        isBusy = false
    }
}

struct ICloudScreen: View {
    @Environment(\.services) private var services
    @Environment(\.openURL) private var openURL
    @Environment(\.dataDeleted) private var dataDeleted
    @State private var model = ICloudModel()

    var body: some View {
        ICloudPage(
            status: model.status, problem: model.problem, isBusy: model.isBusy,
            actions: ICloudActions(
                set: { model.set($0) },
                answer: { choice in
                    Task {
                        await model.answer(choice, services.iCloud)
                        // "Delete it here too" erased this device: back to the welcome.
                        if choice == .deleteHereToo { dataDeleted() }
                    }
                },
                tryAgain: { Task { await model.tryAgain(services.iCloud) } },
                openSettings: {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                })
        )
        .alert(ICloudText.turnOnTitle, isPresented: $model.isAskingTurnOn) {
            Button(ICloudText.turnOn) { Task { await model.turnOn(services.iCloud) } }
                .accessibilityIdentifier("iCloud.turnOn.confirm")
            Button(ICloudText.notNow, role: .cancel) {}
        } message: {
            Text(
                ICloudText.turnOnMessage(
                    bytes: model.status?.estimatedBytes ?? 0, includesBodyData: model.status?.includesBodyData ?? true))
        }
        .confirmationDialog(ICloudText.turnOffTitle, isPresented: $model.isAskingTurnOff, titleVisibility: .visible) {
            Button(ICloudText.keepCopy) { Task { await model.turnOff(services.iCloud, deletingCopy: false) } }
                .accessibilityIdentifier("iCloud.turnOff.keep")
            Button(ICloudText.deleteCopy, role: .destructive) {
                Task { await model.turnOff(services.iCloud, deletingCopy: true) }
            }
            .accessibilityIdentifier("iCloud.turnOff.delete")
            Button(ICloudText.cancel, role: .cancel) {}
        } message: {
            Text(ICloudText.turnOffMessage)
        }
        .navigationTitle(ICloudText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .task { await model.load(services.iCloud) }
    }
}

struct ICloudActions {
    var set: (Bool) -> Void = { _ in }
    var answer: (ICloudChoice) -> Void = { _ in }
    var tryAgain: () -> Void = {}
    var openSettings: () -> Void = {}
}

/// The iCloud screen, top to bottom. Separate from `ICloudScreen` so snapshot tests can draw it.
struct ICloudPage: View {
    let status: ICloudSyncStatus?
    var problem: String?
    var isBusy = false
    var actions = ICloudActions()

    var body: some View {
        SettingsPage(header: SettingsHeader(title: ICloudText.title, lede: ICloudText.lede)) {
            if let status {
                content(status)
            }
        }
    }

    @ViewBuilder
    private func content(_ status: ICloudSyncStatus) -> some View {
        if case .paused(let pause) = status.state {
            SettingsGroup(identifier: "iCloud.question") {
                SettingsNote(ICloudText.pause(pause))
                ForEach(pause.choices, id: \.self) { choice in
                    Button {
                        actions.answer(choice)
                    } label: {
                        NookRow(ICloudText.choice(choice, in: pause), systemImage: Self.image(choice))
                    }
                    .buttonStyle(.nookRow)
                    .disabled(isBusy)
                    .accessibilityIdentifier("iCloud.choice.\(choice.rawValue)")
                }
            }
        }
        if case .deletingCopy(let waiting) = status.state {
            SettingsGroup(identifier: "iCloud.deleting") {
                SettingsNote(ICloudText.deleting(waitingForAccount: waiting))
            }
        }

        SettingsGroup(identifier: "iCloud.switch") {
            SettingsSwitchRow(
                title: ICloudText.switchTitle, detail: ICloudText.switchDetail(isOn: status.state != .off),
                systemImage: "icloud", isOn: status.state != .off, identifier: "iCloud.switch",
                set: { isOn in actions.set(isOn) }
            )
            .disabled(isBusy || Self.isDeleting(status.state))
            if let problem {
                SettingsNote(problem)
            }
        }

        if status.state != .off {
            SettingsGroup(header: ICloudText.statusHeader, identifier: "iCloud.status") {
                SettingsInfoRow(title: ICloudText.savedHere, systemImage: "iphone")
                if status.isUpToDate {
                    SettingsInfoRow(title: ICloudText.allUploaded, systemImage: "checkmark.icloud")
                } else if status.waitingChanges + status.waitingPhotos > 0 {
                    SettingsInfoRow(
                        title: ICloudText.waiting(changes: status.waitingChanges, photos: status.waitingPhotos),
                        systemImage: "icloud.and.arrow.up")
                }
                if let lastConfirmed = status.lastConfirmed {
                    SettingsInfoRow(title: ICloudText.lastConfirmed(lastConfirmed), systemImage: "clock")
                }
                if let problem = status.problem {
                    SettingsNote(ICloudText.problem(problem))
                    Button(action: problem == .storageFull ? actions.openSettings : actions.tryAgain) {
                        NookRow(
                            problem == .storageFull ? ICloudText.openSettings : ICloudText.tryAgain,
                            systemImage: problem == .storageFull ? "gear" : "arrow.clockwise", accessory: .chevron)
                    }
                    .buttonStyle(.nookRow)
                    .disabled(isBusy)
                    .accessibilityIdentifier("iCloud.problem")
                }
            }
        }

        if status.conflictsToReview > 0 || status.fromNewerVersion > 0 || status.notice != nil {
            SettingsGroup(identifier: "iCloud.notes") {
                if status.notice == .reuploadedAfterReset { SettingsNote(ICloudText.reuploaded) }
                if status.conflictsToReview > 0 { SettingsNote(ICloudText.conflicts(status.conflictsToReview)) }
                if status.fromNewerVersion > 0 { SettingsNote(ICloudText.newerVersion(status.fromNewerVersion)) }
            }
        }

        SettingsGroup {
            if !status.includesBodyData { SettingsNote(ICloudText.bodyDataStays) }
            SettingsNote(ICloudText.help)
        }
    }

    private static func isDeleting(_ state: ICloudSyncStatus.State) -> Bool {
        if case .deletingCopy = state { return true }
        return false
    }

    private static func image(_ choice: ICloudChoice) -> String {
        switch choice {
        case .keepOnThisDevice: "iphone"
        case .copyToThisAccount: "person.crop.circle.badge.plus"
        case .uploadAgain: "icloud.and.arrow.up"
        case .deleteHereToo: "trash"
        }
    }
}
