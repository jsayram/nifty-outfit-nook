import DesignSystem
import Models
import SwiftUI

/// What shows when the store on the iPhone couldn't be opened (Phase 21a), instead of onboarding
/// or the tabs. The words come from `docs/decisions/0004-backup-and-recovery.md`, section 7.
/// Nothing was reset or deleted, and the app changes nothing while this shows.
///
/// Export a copy (Phase 21b) saves the raw store and photos, encrypted with a passphrase, for a
/// later version of the app to restore. Try again and Send feedback, the design's other two
/// buttons, aren't here yet: the coordinator's three tries per build already retry at each launch,
/// and Send feedback needs the services this screen can't open.
struct StoreProblemView: View {
    let problem: StoreOpenProblem
    var exporter: (any StoreCopyExporter)?
    @State private var model: BackupsModel?

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: NookSpacing.large) {
                NookEmptyState(
                    StoreProblemText.title(problem), message: StoreProblemText.message(problem),
                    systemImage: "externaldrive.badge.exclamationmark"
                )
                .accessibilityIdentifier("storeProblem")
                if let model {
                    NookButton(BackupsText.exportTitle, systemImage: "square.and.arrow.up", kind: .soft) {
                        model.startExport()
                    }
                    .accessibilityIdentifier("storeProblem.export")
                }
            }
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.top, NookSpacing.xxxLarge)
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
        .modifier(StoreCopySheet(model: model))
        .task {
            guard model == nil, let exporter else { return }
            let export = BackupsModel(service: StoreCopyBackupService(exporter: exporter))
            export.offersCheck = false
            model = export
        }
    }
}

/// The export sheet over the recovery screen.
private struct StoreCopySheet: ViewModifier {
    let model: BackupsModel?

    func body(content: Content) -> some View {
        if let model {
            @Bindable var model = model
            content
                .nookSheet(
                    item: $model.flow, title: { BackupFlowSheet.title($0) }, detents: [.large],
                    onDismiss: { Task { await model.closed() } },
                    content: { flow in BackupFlowSheet(model: model, flow: flow) }
                )
        } else {
            content
        }
    }
}

/// The recovery screen's export, as a backup service that only exports. It makes a store copy,
/// since this build can't read the records.
private struct StoreCopyBackupService: BackupService {
    let exporter: any StoreCopyExporter

    func summary() async throws(BackupError) -> BackupSummary { throw .failed }
    func makePassphrase() -> String { exporter.makePassphrase() }
    func export(passphrase: String) async throws(BackupError) -> BackupFile {
        try await exporter.exportStoreCopy(passphrase: passphrase)
    }
    func discard(_ file: BackupFile) async { await exporter.discard(file) }
    func check(_ url: URL, passphrase: String) async throws(BackupError) -> BackupPreview { throw .failed }
    func restore(_ preview: BackupPreview, as mode: RestoreMode) async throws(BackupError) -> RestoreOutcome {
        throw .failed
    }
    func discardChecked() async {}
    func undoAvailable() async -> UndoRestore? { nil }
    func undoRestore() async throws(BackupError) { throw .nothingToRestore }
}

/// The recovery screen's words.
enum StoreProblemText {
    static func title(_ problem: StoreOpenProblem) -> String {
        switch problem {
        case .newerVersion:
            String(
                localized: "This closet was saved by a newer version", bundle: .module,
                comment: "Recovery screen title: the store is from a newer app version")
        case .notEnoughSpace:
            String(
                localized: "Your closet needs more space to update", bundle: .module,
                comment: "Recovery screen title: not enough free space for the update's safety copy")
        case .updateFailed:
            String(
                localized: "Your closet couldn’t be updated", bundle: .module,
                comment: "Recovery screen title: the store's update failed")
        case .couldNotOpen:
            String(
                localized: "Your closet didn’t open", bundle: .module,
                comment: "Recovery screen title: the store couldn't be opened")
        }
    }

    static func message(_ problem: StoreOpenProblem) -> String {
        switch problem {
        case .newerVersion:
            String(
                localized: "Update Nifty Outfit Nook to open it. Nothing was changed or deleted.", bundle: .module,
                comment: "Recovery screen: the store is from a newer app version")
        case .notEnoughSpace:
            String(
                localized: "Nothing is lost. Free up some space on this iPhone, then open the app again.",
                bundle: .module, comment: "Recovery screen: not enough free space")
        case .updateFailed:
            String(
                localized: "Nothing is lost. The copy from before the update is safe on this iPhone.",
                bundle: .module, comment: "Recovery screen: the store's update failed")
        case .couldNotOpen:
            String(
                localized: "Nothing was deleted. Close the app and open it again.", bundle: .module,
                comment: "Recovery screen: the store couldn't be opened")
        }
    }
}
