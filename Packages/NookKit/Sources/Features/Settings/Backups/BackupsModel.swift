import Foundation
import Models
import Observation

/// Backups (Phase 21b, docs/decisions/0004-backup-and-recovery.md sections 3 and 4): Export a copy,
/// Check a copy, Restore from a copy and Undo restore, on Privacy and terms and Profile.
///
/// One flow runs at a time, in one sheet, step by step. Exporting writes an encrypted file that
/// the Files sheet then saves wherever she picks; the app sends nothing anywhere itself. Checking
/// and restoring open a file she picks, and nothing in the app changes until she chooses Replace
/// or Add what's missing. After a restore or an undo, the root builds every screen again on the
/// restored closet (`BackupRestoredAction`).
@MainActor
@Observable
final class BackupsModel {
    enum Flow: String, Identifiable {
        case export
        case check
        case restore
        var id: String { rawValue }
    }

    enum Step: Equatable {
        /// Export: what goes, and the passphrase.
        case passphrase
        case exporting
        /// Export: the Files sheet is open.
        case saving(BackupFile)
        case exported(name: String)
        /// Check or Restore: a file is picked; its passphrase is needed.
        case unlock(URL)
        case checking(URL)
        /// Check: it works. Restore: choose Replace or Add what's missing.
        case preview(BackupPreview)
        case restoring
        case restored(RestoreOutcome)
        case failed(BackupError)
    }

    enum PassphraseKind: String, CaseIterable, Identifiable {
        case generated
        case own
        var id: String { rawValue }
    }

    private(set) var summary: BackupSummary?
    private(set) var undo: UndoRestore?
    var flow: Flow?
    private(set) var step: Step = .passphrase
    var passphraseKind = PassphraseKind.generated
    private(set) var generated = ""
    var ownPassphrase = ""
    var ownConfirmation = ""
    /// What she types to open a copy. Cleared once it's used.
    var unlockPassphrase = ""
    /// The Files picker is open, for `flow`.
    var isPicking = false
    /// The last restore or undo finished: the root rebuilds the screens when the sheet closes.
    private(set) var needsReload = false

    /// Whether a finished export offers Check this copy. The recovery screen can't check one.
    var offersCheck = true
    /// Set by the screen from its services before it loads.
    @ObservationIgnored var service: (any BackupService)?

    init(service: (any BackupService)? = nil) {
        self.service = service
    }

    // MARK: Loading

    func load() async {
        guard let service else { return }
        summary = try? await service.summary()
        undo = await service.undoAvailable()
    }

    /// Sets what shows directly, for snapshot tests.
    func show(summary: BackupSummary?, undo: UndoRestore? = nil, flow: Flow? = nil, step: Step = .passphrase) {
        self.summary = summary
        self.undo = undo
        self.flow = flow
        self.step = step
        if generated.isEmpty { generated = "K7QM-3XTB-9WFH-P2RD-LV8N-YC4J" }
    }

    // MARK: Export

    func startExport() {
        guard let service else { return }
        generated = service.makePassphrase()
        ownPassphrase = ""
        ownConfirmation = ""
        passphraseKind = .generated
        step = .passphrase
        flow = .export
    }

    /// Why her own passphrase can't be used yet, once she's typed something.
    var passphraseProblem: PassphraseProblem? {
        guard passphraseKind == .own, !ownPassphrase.isEmpty else { return nil }
        return BackupPassphrase.problem(ownPassphrase, confirmation: ownConfirmation)
    }

    var canExport: Bool {
        passphraseKind == .generated || BackupPassphrase.problem(ownPassphrase, confirmation: ownConfirmation) == nil
    }

    func export() async {
        guard let service, canExport else { return }
        let passphrase = passphraseKind == .generated ? generated : ownPassphrase
        step = .exporting
        do {
            step = .saving(try await service.export(passphrase: passphrase))
        } catch {
            step = .failed(error)
        }
        ownPassphrase = ""
        ownConfirmation = ""
    }

    /// The Files sheet closed: saved, or cancelled. The temporary file goes either way.
    func saved(_ file: BackupFile, as name: String?) async {
        await service?.discard(file)
        if let name {
            step = .exported(name: name)
        } else {
            step = .passphrase
        }
    }

    // MARK: Check and Restore

    /// Opens the Files picker for Check a copy or Restore from a copy.
    func pick(for flow: Flow) {
        self.flow = nil
        pickingFlow = flow
        isPicking = true
    }

    @ObservationIgnored private(set) var pickingFlow: Flow?

    func picked(_ url: URL?) {
        guard let url, let flow = pickingFlow else { return }
        unlockPassphrase = ""
        step = .unlock(url)
        self.flow = flow
    }

    func unlock() async {
        guard let service, case .unlock(let url) = step, !unlockPassphrase.isEmpty else { return }
        let passphrase = unlockPassphrase
        step = .checking(url)
        do {
            let preview = try await service.check(url, passphrase: passphrase)
            unlockPassphrase = ""
            step = .preview(preview)
        } catch .wrongPassphrase {
            step = .unlock(url)
            wrongPassphrase = true
        } catch {
            unlockPassphrase = ""
            step = .failed(error)
        }
    }

    /// "That passphrase doesn't open this copy." until she types again.
    var wrongPassphrase = false

    func restore(_ preview: BackupPreview, as mode: RestoreMode) async {
        guard let service else { return }
        step = .restoring
        do {
            step = .restored(try await service.restore(preview, as: mode))
            needsReload = true
        } catch {
            step = .failed(error)
        }
    }

    func undoRestore() async -> Bool {
        guard let service else { return false }
        do {
            try await service.undoRestore()
            needsReload = true
            return true
        } catch {
            undo = await service.undoAvailable()
            return false
        }
    }

    /// The sheet closed. A checked copy that wasn't restored is thrown away.
    func closed() async {
        if case .preview = step { await service?.discardChecked() }
        if case .saving(let file) = step { await service?.discard(file) }
        flow = nil
        step = .passphrase
        unlockPassphrase = ""
        wrongPassphrase = false
        await load()
    }
}
