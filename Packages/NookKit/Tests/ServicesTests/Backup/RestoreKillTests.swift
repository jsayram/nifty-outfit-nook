import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// The app killed at every step of a restore and of Undo restore, then launched again: every run
/// ends with the old closet or the whole restored one, never a mix (0004's test plan, the 20a kill
/// harness's idea in-process).
struct RestoreKillTests {
    static let restoreSteps = [
        "restore.staged", "restore.safetyCopyTaken", "restore.photosMoved", "restore.writing", "restore.saved",
        "restore.verified",
    ]

    /// The same record holding the same value. Two encodings of one value can order their keys
    /// differently, so bytes aren't compared.
    private static func same(_ lhs: StoreRow, _ rhs: StoreRow) -> Bool {
        lhs.id == rhs.id && (RecordCodec.byKind[lhs.kind]?.same(lhs, rhs) ?? (lhs.payload == rhs.payload))
    }

    private static func same(_ lhs: [StoreRow], _ rhs: [StoreRow]) -> Bool {
        lhs.count == rhs.count && lhs.allSatisfy { row in rhs.contains { same($0, row) } }
    }

    private static func kill(at checkpoint: String, _ body: () throws -> Void) {
        #expect(throws: StoreCheckpoint.Kill(checkpoint: checkpoint)) {
            let handler: @Sendable (String) throws -> Void = { name in
                if name == checkpoint { throw StoreCheckpoint.Kill(checkpoint: checkpoint) }
            }
            try StoreCheckpoint.$handler.withValue(handler) {
                try body()
            }
        }
    }

    @Test(arguments: restoreSteps, [RestoreMode.replace, .addMissing])
    func aKillDuringARestoreLeavesOneClosetOrTheOther(at checkpoint: String, mode: RestoreMode) async throws {
        // The copy: the demo closet. The phone: something else entirely.
        let source = try BackupTestBed("kill-source")
        try await source.seedDemo()
        let file = try await source.export()
        let phone = try BackupTestBed("kill-phone")
        try await phone.storage.closet.save(
            Garment(id: "g-only-here", name: "Only on this phone", category: .top, addedAt: TestTime.now))
        try await phone.storage.onboarding.complete(startingCloset: .empty)
        let before = try phone.rows()
        let copy = try RestoreChecker(location: phone.location).check(file.url, passphrase: BackupTestBed.passphrase)
        let expected = RestorePlan.make(copy: copy.rows, phone: before, mode: mode, now: phone.today)

        Self.kill(at: checkpoint) { _ = try phone.committer().restoreThrowing(copy, as: mode) }
        _ = try phone.relaunch()

        let after = try phone.rows()
        let restored = Dictionary(expected.rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let isOld = Self.same(after, before)
        let isNew =
            restored.values.allSatisfy { row in after.contains { Self.same($0, row) } }
            && (mode == .addMissing
                || after.filter { RecordCodec.restoredKinds.contains($0.kind) }.count == restored.count)
        #expect(isOld != isNew, "after a kill at \(checkpoint): old \(isOld), new \(isNew)")
        let savedYet =
            Self.restoreSteps.firstIndex(of: checkpoint)! >= Self.restoreSteps.firstIndex(of: "restore.saved")!
        #expect(isNew == savedYet)
        // A restore that didn't happen leaves no safety copy behind; one that did keeps it for Undo.
        #expect(FileManager.default.fileExists(atPath: phone.location.safetyCopy.path) == savedYet)
        #expect(!FileManager.default.fileExists(atPath: phone.location.staging.path))
    }

    /// Killed after Undo's save: the next launch finishes putting the photos back.
    @Test func aKillDuringUndoFinishesAtTheNextLaunch() async throws {
        let phone = try BackupTestBed("kill-undo")
        try await phone.seedDemo()
        let file = try await phone.export()
        let before = try phone.rows()
        let photosBefore = try photoHashes(phone.photos)
        let service = phone.service()
        try await phone.storage.closet.save(
            Garment(id: "g-after", name: "Added after the export", category: .top, addedAt: TestTime.now))
        let withExtra = try phone.rows()
        _ = try await service.restore(
            try await service.check(file.url, passphrase: BackupTestBed.passphrase), as: .replace)
        expectSameRecords(try phone.rows(), before)

        var journal = try #require(try phone.committer().readJournal())
        journal.step = .undoing
        try JSONEncoder().encode(journal).write(to: phone.location.restoreJournal)
        Self.kill(at: "undo.saved") { try phone.committer().undoThrowing() }
        _ = try phone.relaunch()
        expectSameRecords(try phone.rows(), withExtra)
        #expect(try photoHashes(phone.photos) == photosBefore)
        #expect(!FileManager.default.fileExists(atPath: phone.location.safetyCopy.path))
    }
}
