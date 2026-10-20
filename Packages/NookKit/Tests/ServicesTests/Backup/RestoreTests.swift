import Fixtures
import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

@testable import Services

/// Replace, Add what's missing, deletion markers and Undo restore (0004's test plan, "Restore").
struct RestoreTests {
    private static let garments = BackupTestBed.demo.garments

    /// A copy of the demo closet, and a phone that has moved on since: one piece renamed, one new,
    /// one from the copy deleted for good.
    private static func phoneThatMovedOn() async throws -> (BackupTestBed, BackupFile, before: [StoreRow]) {
        let phone = try BackupTestBed("moved-on")
        try await phone.seedDemo()
        let file = try await phone.export()
        try await phone.storage.closet.update(garments[5].id) { $0.name = "Renamed on the phone" }
        try await phone.storage.closet.save(
            Garment(id: "g-new", name: "New coat", category: .layer, addedAt: TestTime.now))
        try await phone.storage.closet.delete(garments[6].id, at: TestTime.day(-1))
        try await phone.storage.closet.deletePermanently(garments[6].id)
        return (phone, file, try phone.rows())
    }

    @Test func replaceIntoAFullClosetTakesASafetyCopyAndUndoBringsItBack() async throws {
        let (phone, file, before) = try await Self.phoneThatMovedOn()
        let photosBefore = try photoHashes(phone.photos)
        let service = phone.service()
        let preview = try await service.check(file.url, passphrase: BackupTestBed.passphrase)
        #expect(preview.deletedForGood == 1)
        let outcome = try await service.restore(preview, as: .replace)
        #expect(outcome.deletedForGood == 1)
        #expect(outcome.undoUntil == phone.today.addingTimeInterval(7 * 86_400))

        let after = try phone.rows()
        let names = Dictionary(
            uniqueKeysWithValues: after.filter { $0.kind == "garment" }.compactMap { row in
                (try? RecordPayload.decode(Garment.self, from: row.payload, version: row.payloadVersion)).map {
                    (row.key, $0.name)
                }
            })
        #expect(names[Self.garments[5].id.rawValue] == Self.garments[5].name)
        #expect(names["g-new"] == nil)
        #expect(names[Self.garments[6].id.rawValue] == nil, "a piece deleted for good came back")
        #expect(after.contains { $0.kind == "deletion" && $0.key == Self.garments[6].id.rawValue })

        let safety = phone.location.safetyCopy
        #expect(try safety.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(await service.undoAvailable() != nil)
        try await service.undoRestore()
        expectSameRecords(try phone.rows(), before)
        #expect(try photoHashes(phone.photos) == photosBefore)
        #expect(await service.undoAvailable() == nil)
        #expect(!FileManager.default.fileExists(atPath: safety.path))
    }

    @Test func addWhatsMissingAddsKeepsAndRemovesNothing() async throws {
        let (phone, file, before) = try await Self.phoneThatMovedOn()
        // The copy also has a piece this phone deleted from Recently deleted and doesn't have.
        let service = phone.service()
        let preview = try await service.check(file.url, passphrase: BackupTestBed.passphrase)
        let outcome = try await service.restore(preview, as: .addMissing)
        let after = try phone.rows()

        // Nothing on the phone was removed or changed, apart from the review copies added.
        let beforeIDs = Set(before.map(\.id))
        #expect(beforeIDs.isSubset(of: Set(after.map(\.id))))
        expectSameRecords(
            after.filter { beforeIDs.contains($0.id) }, before)
        // The renamed piece is a conflict, kept for review with the copy's version.
        let conflict = try #require(after.first { $0.kind == "restoreConflict" })
        #expect(conflict.key == "garment/\(Self.garments[5].id.rawValue)")
        #expect(outcome.conflicts >= 1)
        // The purged piece didn't come back.
        #expect(!after.contains { $0.kind == "garment" && $0.key == Self.garments[6].id.rawValue })
    }

    @Test func addWhatsMissingIntoAnEmptyPhoneAddsEverything() async throws {
        let phone = try BackupTestBed("source")
        try await phone.seedDemo()
        let file = try await phone.export()
        let newPhone = try BackupTestBed("empty-add")
        let service = newPhone.service()
        let preview = try await service.check(file.url, passphrase: BackupTestBed.passphrase)
        let outcome = try await service.restore(preview, as: .addMissing)
        #expect(outcome.conflicts == 0)
        expectSameRecords(try newPhone.rows(), try phone.rows())
    }

    /// A piece listed in the copy's own deletion markers never comes back by either path, even on
    /// a phone that never heard of it.
    @Test(arguments: [RestoreMode.replace, .addMissing])
    func theCopysDeletionMarkersAreObeyed(_ mode: RestoreMode) async throws {
        let phone = try BackupTestBed("markers")
        try await phone.seedDemo()
        // A copy that holds a piece and also says it was deleted for good: only a crafted or
        // damaged copy could, and the marker wins.
        var rows = try phone.rows()
        rows.append(
            StoreRow(
                kind: "deletion", key: Self.garments[0].id.rawValue, payloadVersion: 1,
                payload: try RecordPayload.encode(StoredDeletion(deletedAt: TestTime.now))))
        let copy = StagedCopy(
            id: UUID(), folder: phone.root.appending(path: "none"), manifest: CraftedArchive.manifest(files: [:]),
            rows: try RestoreChecker.checked(rows))
        let newPhone = try BackupTestBed("markers-new")
        let outcome = try newPhone.committer().restore(copy, as: mode)
        #expect(outcome.deletedForGood == 1)
        #expect(!(try newPhone.rows()).contains { $0.kind == "garment" && $0.key == Self.garments[0].id.rawValue })
    }

    /// A try-on picture that shows a piece deleted for good stays deleted too, by either path:
    /// the copy still has the picture, and this phone has since purged the piece.
    @Test(arguments: [RestoreMode.replace, .addMissing])
    func picturesOfAPurgedPieceDontComeBack(_ mode: RestoreMode) async throws {
        let phone = try BackupTestBed("purged-pictures")
        try await phone.seedDemo()
        let look = try #require(BackupTestBed.demo.looks.first { !$0.garmentIDs.isEmpty })
        let piece = look.garmentIDs[0]
        try await phone.storage.pictures.save(
            TryOnPicture(id: "t-purged", of: look, image: .simulated, createdAt: TestTime.now))
        let file = try await phone.export()
        try await phone.storage.pictures.delete("t-purged")
        try await phone.storage.closet.delete(piece, at: TestTime.day(-1))
        try await phone.storage.closet.deletePermanently(piece)

        let service = phone.service()
        _ = try await service.restore(
            try await service.check(file.url, passphrase: BackupTestBed.passphrase), as: mode)
        let after = try phone.rows()
        #expect(!after.contains { $0.kind == "picture" && $0.key == "t-purged" })
        #expect(!after.contains { $0.kind == "garment" && $0.key == piece.rawValue })
    }

    @Test func aRestoreNeedsACheckedCopy() async throws {
        let phone = try BackupTestBed("unchecked")
        let preview = BackupPreview(id: UUID(), createdAt: TestTime.now, inCopy: .init(), onPhone: .init())
        await #expect(throws: BackupError.nothingToRestore) {
            try await phone.service().restore(preview, as: .replace)
        }
        await #expect(throws: BackupError.nothingToRestore) { try await phone.service().undoRestore() }
    }

    /// Not enough room for the safety copy: the restore doesn't start, and says how much it needs.
    @Test func aRestoreWithoutSpaceForItsSafetyCopyDoesntStart() async throws {
        let (phone, file, before) = try await Self.phoneThatMovedOn()
        let preview = try await phone.service().check(file.url, passphrase: BackupTestBed.passphrase)
        var committer = phone.committer()
        committer.freeSpace = { 1_000 }
        let checker = RestoreChecker(location: phone.location)
        let copy = try checker.check(file.url, passphrase: BackupTestBed.passphrase)
        #expect(preview.inCopy == RestoreChecker.preview(of: copy, phone: before).inCopy)
        #expect {
            try committer.restore(copy, as: .replace)
        } throws: { error in
            if case BackupError.notEnoughSpace = error { return true }
            return false
        }
        expectSameRecords(try phone.rows(), before)
        #expect(!FileManager.default.fileExists(atPath: phone.location.safetyCopy.path))
    }

    /// The safety copy goes 7 days after the restore, at launch, and at once with Delete my data.
    @Test func theSafetyCopyExpiresAndDeleteMyDataRemovesIt() async throws {
        let (phone, file, _) = try await Self.phoneThatMovedOn()
        let service = phone.service()
        _ = try await service.restore(
            try await service.check(file.url, passphrase: BackupTestBed.passphrase), as: .replace)
        #expect(FileManager.default.fileExists(atPath: phone.location.safetyCopy.path))

        phone.committer(now: phone.today.addingTimeInterval(6 * 86_400)).resume()
        #expect(FileManager.default.fileExists(atPath: phone.location.safetyCopy.path))
        phone.committer(now: phone.today.addingTimeInterval(7 * 86_400)).resume()
        #expect(!FileManager.default.fileExists(atPath: phone.location.safetyCopy.path))
        #expect(!FileManager.default.fileExists(atPath: phone.location.restoreJournal.path))

        _ = try await service.restore(
            try await service.check(file.url, passphrase: BackupTestBed.passphrase), as: .replace)
        #expect(FileManager.default.fileExists(atPath: phone.location.safetyCopy.path))
        for (_, store) in phone.storage.erasableData { try await store.eraseAll() }
        for folder in [
            phone.location.safetyCopy, phone.location.photos, phone.location.staging, phone.location.exports,
        ] {
            #expect(!FileManager.default.fileExists(atPath: folder.path), "\(folder.lastPathComponent) is left")
        }
        #expect(!(try phone.rows()).contains { $0.kind == "restoreConflict" || $0.kind == "deletion" })
    }

    /// A piece deleted for good leaves a marker with no content, in the same save.
    @Test func deletingForGoodLeavesAMarker() async throws {
        let phone = try BackupTestBed("marker")
        try await phone.storage.closet.save(Self.garments[0])
        try await phone.storage.closet.delete(Self.garments[0].id, at: TestTime.day(-40))
        #expect(try await phone.storage.closet.purgeExpired(asOf: TestTime.now) == [Self.garments[0].id])
        let marker = try #require(try phone.rows().first { $0.kind == "deletion" })
        #expect(marker.key == Self.garments[0].id.rawValue)
        let value = try RecordPayload.decode(StoredDeletion.self, from: marker.payload, version: marker.payloadVersion)
        #expect(String(decoding: try RecordPayload.encode(value), as: UTF8.self).contains("deletedAt"))
        #expect(!String(decoding: marker.payload, as: UTF8.self).contains(Self.garments[0].name))
    }
}
