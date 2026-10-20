import DesignSystem
import Models
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A Nifty Outfit Nook copy, `.nookbackup` (declared in the app's `Configs/AppInfo.plist`).
    nonisolated static let nookBackup = UTType(exportedAs: "com.jsayram.niftyoutfitnook.backup", conformingTo: .data)
}

/// Backups (Phase 21b), pushed from Privacy and terms and Profile. See `BackupsModel`.
struct BackupsScreen: View {
    @Environment(\.services) private var services
    @Environment(\.backupRestored) private var backupRestored
    @State private var model = BackupsModel()
    @State private var isAskingUndo = false

    var body: some View {
        BackupsPage(
            model: model,
            open: { flow in
                switch flow {
                case .export: model.startExport()
                case .check, .restore: model.pick(for: flow)
                }
            }, undo: { isAskingUndo = true }
        )
        .navigationTitle(BackupsText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .fileImporter(
            isPresented: $model.isPicking,
            allowedContentTypes: [.nookBackup]
        ) { result in
            model.picked(try? result.get())
        }
        .nookSheet(
            item: $model.flow, title: { BackupFlowSheet.title($0) },
            detents: [.large],
            onDismiss: {
                Task {
                    let reload = model.needsReload
                    await model.closed()
                    if reload { backupRestored() }
                }
            }
        ) { flow in
            BackupFlowSheet(model: model, flow: flow)
        }
        .alert(BackupsText.undoTitle, isPresented: $isAskingUndo) {
            Button(BackupsText.undoTitle, role: .destructive) {
                Task { if await model.undoRestore() { backupRestored() } }
            }
            Button(BackupsText.cancel, role: .cancel) {}
        } message: {
            Text(BackupsText.askUndoMessage)
        }
        .task {
            model.service = services.backups
            await model.load()
        }
    }
}

/// Backups, top to bottom. Separate from `BackupsScreen` so snapshot tests can draw it.
struct BackupsPage: View {
    let model: BackupsModel
    var open: (BackupsModel.Flow) -> Void = { _ in }
    var undo: () -> Void = {}

    var body: some View {
        SettingsPage(header: SettingsHeader(title: BackupsText.title, lede: BackupsText.lede)) {
            SettingsGroup(identifier: "backups.actions") {
                row(
                    .export, title: BackupsText.exportTitle, detail: BackupsText.exportDetail,
                    image: "square.and.arrow.up")
                row(.check, title: BackupsText.checkTitle, detail: BackupsText.checkDetail, image: "checkmark.shield")
                row(
                    .restore, title: BackupsText.restoreTitle, detail: BackupsText.restoreDetail,
                    image: "arrow.counterclockwise")
            }

            if let summary = model.summary {
                SettingsGroup(header: BackupsText.whatGoesHeader, identifier: "backups.summary") {
                    BackupCountRows(counts: summary.counts)
                    if summary.includesBodyData {
                        SettingsInfoRow(title: BackupsText.bodyData, systemImage: "ruler")
                    }
                    if summary.includesTryOnPhoto {
                        SettingsInfoRow(title: BackupsText.tryOnPhoto, systemImage: "person.crop.square")
                    }
                    SettingsNote(BackupsText.estimatedSize(summary.estimatedBytes))
                }
            }

            if let pending = model.undo {
                SettingsGroup(identifier: "backups.undo") {
                    Button(action: undo) {
                        NookRow(
                            BackupsText.undoTitle, subtitle: BackupsText.undoDetail(pending),
                            systemImage: "arrow.uturn.backward", accessory: .chevron)
                    }
                    .buttonStyle(.nookRow)
                    .accessibilityIdentifier("backups.undo")
                }
            }

            SettingsGroup {
                SettingsNote(BackupsText.nowhereElse)
            }
        }
    }

    private func row(_ flow: BackupsModel.Flow, title: String, detail: String, image: String) -> some View {
        Button {
            open(flow)
        } label: {
            NookRow(title, subtitle: detail, systemImage: image, accessory: .chevron)
        }
        .buttonStyle(.nookRow)
        .accessibilityIdentifier("backups.\(flow.rawValue)")
    }
}

/// Pieces, Recently deleted, looks, suitcases, pictures and drafts, one row each when there are any.
struct BackupCountRows: View {
    let counts: BackupCounts

    var body: some View {
        SettingsInfoRow(
            title: String(
                localized: "\(counts.pieces) pieces", bundle: .module,
                comment: "Source plate: how many pieces the source has"),
            detail: counts.recentlyDeleted > 0 ? Self.recentlyDeleted(counts.recentlyDeleted) : nil,
            systemImage: "hanger")
        if counts.looks > 0 {
            SettingsInfoRow(
                title: String(
                    localized: "\(counts.looks) looks", bundle: .module,
                    comment: "Saved Looks: how many looks she saved"),
                systemImage: "sparkles")
        }
        if counts.suitcases > 0 {
            SettingsInfoRow(
                title: String(
                    localized: "\(counts.suitcases) suitcases", bundle: .module,
                    comment: "Closet tile: how many suitcases she has"),
                systemImage: "suitcase")
        }
        if counts.pictures > 0 {
            SettingsInfoRow(
                title: String(
                    localized: "\(counts.pictures) pictures", bundle: .module, comment: "How many try-on pictures"),
                systemImage: "photo.on.rectangle")
        }
        if counts.drafts > 0 {
            SettingsInfoRow(
                title: String(
                    localized: "\(counts.drafts) drafts", bundle: .module,
                    comment: "Delete my data: how many unsaved drafts"),
                systemImage: "square.and.pencil")
        }
    }

    static func recentlyDeleted(_ count: Int) -> String {
        String(
            localized: "And \(count) in Recently deleted", bundle: .module,
            comment: "Backups: pieces in Recently deleted, under the piece count")
    }
}

/// After a restore or Undo restore: the root builds every screen again on the restored closet.
/// The root view sets it; elsewhere it does nothing.
struct BackupRestoredAction: Sendable {
    let action: @MainActor @Sendable () -> Void

    @MainActor func callAsFunction() {
        action()
    }
}

extension EnvironmentValues {
    @Entry var backupRestored = BackupRestoredAction {}
}
