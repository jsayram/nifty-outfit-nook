import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// Backups the Phase 21b build made, before the schema and payload change of Phase 21c, still
/// restore both ways (Replace, and Add what's missing), and a backup made now carries the new
/// fields and says so, so the 21b build refuses it instead of dropping them.
struct OlderBackupTests {
    // MARK: A records copy (format 1, payload 1)

    @Test func aPhase21bExportRestoresWithReplace() async throws {
        let phone = try BackupTestBed("21b-replace")
        try phone.seedLarge(5)
        let service = phone.service()
        let preview = try await service.check(
            try Phase21bFixtures.url("records-demo-1", "nookbackup"), passphrase: Phase21bFixtures.recordsPassphrase)
        #expect(preview.photos == 3 && preview.includesBodyData && preview.includesTryOnPhoto)
        _ = try await service.restore(preview, as: .replace)
        phone.storage.reload()
        expectSameRecords(try phone.rows(), try Phase21bFixtures.rows())
        #expect(phone.photos.ids().count == 3)
        // Her pieces read with no other names or type, and take them from here on.
        try await expectNewFieldsWork(in: phone)
    }

    @Test func aPhase21bExportRestoresWithAddWhatsMissing() async throws {
        let phone = try BackupTestBed("21b-add")
        // This phone has one of the copy's pieces with other names and a type added since, and a
        // piece of its own the copy doesn't have.
        let fixture = try Phase21bFixtures.rows()
        let navy = try #require(fixture.first { $0.id == "garment/g-navy-trousers" })
        var changed = try RecordPayload.decode(Garment.self, from: navy.payload, version: navy.payloadVersion)
        changed.otherNames = ["Interview pants"]
        changed.subKind = .trousers
        try await phone.storage.closet.save(changed)
        let own = Garment(
            id: "g-own", name: "Sage cardigan", otherNames: ["Cozy one"], category: .layer, subKind: .cardigan,
            addedAt: TestTime.now)
        try await phone.storage.closet.save(own)
        let before = try phone.rows()

        let service = phone.service()
        let preview = try await service.check(
            try Phase21bFixtures.url("records-demo-1", "nookbackup"), passphrase: Phase21bFixtures.recordsPassphrase)
        let outcome = try await service.restore(preview, as: .addMissing)
        phone.storage.reload()
        let after = try phone.rows()

        // Nothing on the phone was removed or changed; its other names and types stay.
        expectSameRecords(after.filter { Set(before.map(\.id)).contains($0.id) }, before)
        #expect(try await phone.storage.closet.garment("g-navy-trousers") == changed)
        #expect(try await phone.storage.closet.garment("g-own") == own)
        // Everything else in the copy was added.
        let missing = fixture.filter { row in !before.contains { $0.id == row.id } }
        expectSameRecords(
            after.filter { row in missing.contains { $0.id == row.id } }, missing,
            kinds: Set(missing.map(\.kind)).subtracting(["onboarding"]))
        // The copy's older version of the changed piece is kept for review, not written over hers.
        #expect(outcome.conflicts == 1)
        #expect(after.contains { $0.kind == "restoreConflict" && $0.key == "garment/g-navy-trousers" })
    }

    /// The first backup fixture (21b's own, three pieces) by Add what's missing, as Replace is
    /// tested in `BackupTamperTests.theFormatOneFixtureRestores`.
    @Test func theFormatOneFixtureRestoresWithAddWhatsMissing() async throws {
        let phone = try BackupTestBed("fixture-1-add")
        let service = phone.service()
        let preview = try await service.check(
            try Phase21bFixtures.url("format-1", "nookbackup"), passphrase: "format version one fixture")
        let outcome = try await service.restore(preview, as: .addMissing)
        #expect(outcome.conflicts == 0)
        phone.storage.reload()
        #expect(
            Set(try await phone.storage.closet.garments().map(\.id))
                == Set(BackupTestBed.demo.garments.prefix(3).map(\.id)))
    }

    // MARK: A store copy (schema version 1)

    /// The recovery screen's copy from the 21b build holds a schema version 1 store. A restore
    /// opens it in staging through the migration coordinator, which migrates it to version 2
    /// first, then restores every record.
    @Test(arguments: [RestoreMode.replace, .addMissing])
    func aPhase21bStoreCopyMigratesInStagingAndRestores(_ mode: RestoreMode) async throws {
        let phone = try BackupTestBed("21b-store-copy")
        let copy = try RestoreChecker(location: phone.location).check(
            try Phase21bFixtures.url("store-copy-1", "nookbackup"), passphrase: Phase21bFixtures.storeCopyPassphrase)
        #expect(copy.manifest.kind == .storeCopy && copy.manifest.storeVersion == 1)
        // The staged store was migrated to version 2 through the journal.
        let staged = StoreLocation(directory: copy.folder.appending(path: "store", directoryHint: .isDirectory))
        #expect(MigrationCoordinator<NookMigrationPlan>(location: staged).storedVersion() == 2)
        #expect(try MigrationCoordinator<NookMigrationPlan>(location: staged).readJournal()?.step == .verified)

        let outcome = try phone.committer().restore(copy, as: mode)
        #expect(outcome.conflicts == 0)
        phone.storage.reload()
        expectSameRecords(try phone.rows(), try Phase21bFixtures.rows())
        #expect(phone.photos.ids().count == 3)
        try await expectNewFieldsWork(in: phone)
    }

    // MARK: A copy made now

    /// An export now carries other names and types, at payload version 2. The 21b build checks
    /// that version before reading a record (`RestoreChecker`: payload newer than it knows), so
    /// it refuses the copy with "from a newer version" rather than restore it without them.
    @Test func aNewExportCarriesTheNewFields() async throws {
        let phone = try BackupTestBed("21c-export")
        let piece = Garment(
            id: "g-sage", name: "Sage cardigan", otherNames: ["Green cardigan", "Cozy one"], category: .layer,
            subKind: .cardigan, addedAt: TestTime.now)
        try await phone.storage.closet.save(piece)
        let file = try await phone.export()
        let staging = phone.root.appending(path: "look-inside", directoryHint: .isDirectory)
        try BackupLocation.prepare(staging)
        let manifest = try BackupArchiveReader().extract(file.url, passphrase: BackupTestBed.passphrase, into: staging)
        #expect(manifest.formatVersion == 1 && manifest.payloadVersion == 2 && manifest.storeVersion == 2)
        let garments = try String(contentsOf: staging.appending(path: "records/garment.json"), encoding: .utf8)
        #expect(garments.contains("\"otherNames\"") && garments.contains("\"cardigan\""))

        let newPhone = try BackupTestBed("21c-restore")
        let service = newPhone.service()
        _ = try await service.restore(
            try await service.check(file.url, passphrase: BackupTestBed.passphrase), as: .replace)
        newPhone.storage.reload()
        #expect(try await newPhone.storage.closet.garment("g-sage") == piece)
    }

    // MARK: Helpers

    /// After a restore from an older copy, a restored piece takes other names and a type, and
    /// keeps them through a relaunch.
    private func expectNewFieldsWork(in phone: BackupTestBed) async throws {
        let garment = try await phone.storage.closet.garment("g-navy-trousers")
        #expect(garment.otherNames.isEmpty && garment.subKind == nil)
        try await phone.storage.closet.update("g-navy-trousers") {
            $0.otherNames = ["Interview pants"]
            $0.subKind = .trousers
        }
        let relaunched = try phone.relaunch()
        let saved = try await relaunched.closet.garment("g-navy-trousers")
        #expect(saved.otherNames == ["Interview pants"] && saved.subKind == .trousers)
    }
}
