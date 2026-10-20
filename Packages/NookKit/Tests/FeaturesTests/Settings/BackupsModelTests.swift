import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Backups' steps (Phase 21b) against a scripted service: export with either passphrase, a wrong
/// passphrase and a right one, Replace, Undo restore, and that nothing restores without a choice.
@MainActor
struct BackupsModelTests {
    @Test func exportWithTheGeneratedPassphrase() async {
        let service = ScriptedBackups()
        let model = BackupsModel(service: service)
        await model.load()
        #expect(model.summary?.counts.pieces == 21)
        model.startExport()
        #expect(model.flow == .export && model.generated == "TEST-PASS-PHRA-SE12-3456-7890")
        #expect(model.canExport)
        await model.export()
        guard case .saving(let file) = model.step else {
            Issue.record("expected the Files sheet, got \(model.step)")
            return
        }
        #expect(await service.exportedWith == ["TEST-PASS-PHRA-SE12-3456-7890"])
        await model.saved(file, as: "Nifty Outfit Nook 2026-10-14.nookbackup")
        #expect(model.step == .exported(name: "Nifty Outfit Nook 2026-10-14.nookbackup"))
        #expect(await service.discarded == 1)
    }

    @Test func herOwnPassphraseMustBeLongEnoughAndTypedTwice() async {
        let service = ScriptedBackups()
        let model = BackupsModel(service: service)
        model.startExport()
        model.passphraseKind = .own
        #expect(!model.canExport && model.passphraseProblem == nil)
        model.ownPassphrase = "too short"
        #expect(model.passphraseProblem == .tooShort && !model.canExport)
        model.ownPassphrase = "long enough to use"
        model.ownConfirmation = "long enough to us"
        #expect(model.passphraseProblem == .doesntMatch)
        model.ownConfirmation = "long enough to use"
        #expect(model.canExport)
        await model.export()
        #expect(await service.exportedWith == ["long enough to use"])
        #expect(model.ownPassphrase.isEmpty && model.ownConfirmation.isEmpty)
    }

    @Test func cancellingTheFilesSheetGoesBackAndDeletesTheFile() async {
        let service = ScriptedBackups()
        let model = BackupsModel(service: service)
        model.startExport()
        await model.export()
        guard case .saving(let file) = model.step else { return }
        await model.saved(file, as: nil)
        #expect(model.step == .passphrase)
        #expect(await service.discarded == 1)
    }

    @Test func aWrongPassphraseAsksAgainThenTheRightOneShowsThePreview() async {
        let service = ScriptedBackups()
        let model = BackupsModel(service: service)
        model.pick(for: .restore)
        #expect(model.isPicking)
        model.picked(URL(filePath: "/tmp/copy.nookbackup"))
        #expect(model.flow == .restore)
        model.unlockPassphrase = "the wrong one"
        await model.unlock()
        #expect(model.wrongPassphrase)
        #expect(model.step == .unlock(URL(filePath: "/tmp/copy.nookbackup")))
        model.unlockPassphrase = ScriptedBackups.passphrase
        await model.unlock()
        guard case .preview(let preview) = model.step else {
            Issue.record("expected the preview, got \(model.step)")
            return
        }
        #expect(model.unlockPassphrase.isEmpty)
        #expect(await service.restoredModes.isEmpty, "nothing restores before she chooses")

        await model.restore(preview, as: .replace)
        #expect(await service.restoredModes == [.replace])
        guard case .restored = model.step else {
            Issue.record("expected restored, got \(model.step)")
            return
        }
        #expect(model.needsReload)
    }

    @Test func closingAPreviewThrowsTheCheckedCopyAway() async {
        let service = ScriptedBackups()
        let model = BackupsModel(service: service)
        model.pick(for: .check)
        model.picked(URL(filePath: "/tmp/copy.nookbackup"))
        model.unlockPassphrase = ScriptedBackups.passphrase
        await model.unlock()
        await model.closed()
        #expect(await service.discardedChecks == 1)
        #expect(model.flow == nil && !model.needsReload)
    }

    @Test func aDamagedCopySaysSo() async {
        let service = ScriptedBackups(checkFails: .damaged)
        let model = BackupsModel(service: service)
        model.pick(for: .restore)
        model.picked(URL(filePath: "/tmp/copy.nookbackup"))
        model.unlockPassphrase = ScriptedBackups.passphrase
        await model.unlock()
        #expect(model.step == .failed(.damaged))
        #expect(BackupsText.failed(.damaged) == "This copy is damaged or incomplete, so nothing was restored.")
    }

    @Test func undoRestoreAsksTheRootToReload() async {
        let service = ScriptedBackups()
        let model = BackupsModel(service: service)
        await model.load()
        #expect(model.undo != nil)
        #expect(await model.undoRestore())
        #expect(model.needsReload)
    }
}

/// A backup service that answers from a script and records what it was asked.
actor ScriptedBackups: BackupService {
    static let passphrase = "the right passphrase"
    private(set) var exportedWith: [String] = []
    private(set) var discarded = 0
    private(set) var discardedChecks = 0
    private(set) var restoredModes: [RestoreMode] = []
    let checkFails: BackupError?

    init(checkFails: BackupError? = nil) {
        self.checkFails = checkFails
    }

    static let preview = BackupPreview(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!, createdAt: TestTime.day(-11),
        inCopy: BackupCounts(pieces: 21, recentlyDeleted: 2, looks: 6, suitcases: 6, pictures: 3, drafts: 1),
        onPhone: BackupCounts(pieces: 4, looks: 1), photos: 24, includesBodyData: true, includesTryOnPhoto: true,
        deletedForGood: 1, missingReferences: 0)

    func summary() async throws(BackupError) -> BackupSummary {
        BackupSummary(
            counts: BackupCounts(pieces: 21, recentlyDeleted: 2, looks: 6, suitcases: 6, pictures: 3, drafts: 1),
            photos: 24, estimatedBytes: 112_000_000, includesBodyData: true, includesTryOnPhoto: true)
    }

    nonisolated func makePassphrase() -> String { "TEST-PASS-PHRA-SE12-3456-7890" }

    func export(passphrase: String) async throws(BackupError) -> BackupFile {
        exportedWith.append(passphrase)
        return BackupFile(url: URL(filePath: "/tmp/Export/x/Nifty Outfit Nook 2026-10-14.nookbackup"), bytes: 1_000)
    }

    func discard(_ file: BackupFile) async { discarded += 1 }

    func check(_ url: URL, passphrase: String) async throws(BackupError) -> BackupPreview {
        if let checkFails { throw checkFails }
        guard passphrase == Self.passphrase else { throw .wrongPassphrase }
        return Self.preview
    }

    func restore(_ preview: BackupPreview, as mode: RestoreMode) async throws(BackupError) -> RestoreOutcome {
        restoredModes.append(mode)
        return RestoreOutcome(
            counts: preview.inCopy, added: 40, conflicts: 0, deletedForGood: 1, undoUntil: TestTime.day(7))
    }

    func discardChecked() async { discardedChecks += 1 }

    func undoAvailable() async -> UndoRestore? { UndoRestore(takenAt: TestTime.day(-1), until: TestTime.day(6)) }

    func undoRestore() async throws(BackupError) {}
}
