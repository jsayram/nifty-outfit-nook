import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// A copy that's been changed, cut short or opened with the wrong passphrase stops before the
/// preview, and nothing in the app changes (0004's test plan, "Export format").
struct BackupTamperTests {
    /// Checks `file` on a phone holding one piece, expecting `error`, then proves nothing changed:
    /// the same records, nothing left in staging.
    private static func expectRefused(
        _ file: URL, passphrase: String = BackupTestBed.passphrase, _ error: BackupError,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let phone = try BackupTestBed("refused")
        try await phone.storage.closet.save(BackupTestBed.demo.garments[0])
        let before = try phone.rows()
        await #expect(throws: error, sourceLocation: sourceLocation) {
            try await phone.service().check(file, passphrase: passphrase)
        }
        expectSameRecords(try phone.rows(), before, sourceLocation: sourceLocation)
        let staged = (try? FileManager.default.contentsOfDirectory(atPath: phone.location.staging.path)) ?? []
        #expect(staged.isEmpty, "staging kept \(staged)", sourceLocation: sourceLocation)
    }

    private static func demoExport() async throws -> (BackupTestBed, Data) {
        let phone = try BackupTestBed("tamper")
        try await phone.seedDemo()
        let file = try await phone.export()
        return (phone, try Data(contentsOf: file.url))
    }

    private static func write(_ data: Data, in phone: BackupTestBed) throws -> URL {
        let url = phone.root.appending(path: "changed-\(UUID().uuidString).nookbackup")
        try data.write(to: url)
        return url
    }

    @Test func aWrongPassphraseOpensNothing() async throws {
        let (phone, data) = try await Self.demoExport()
        let file = try Self.write(data, in: phone)
        try await Self.expectRefused(file, passphrase: "not the passphrase at all", .wrongPassphrase)
        try await Self.expectRefused(file, passphrase: "short", .wrongPassphrase)
    }

    /// One changed byte in the prologue, the header, the middle or the end.
    @Test(arguments: [8, 200, 4_000, 60_000, -40])
    func oneChangedByteFails(at offset: Int) async throws {
        let (phone, original) = try await Self.demoExport()
        var data = original
        let index = offset >= 0 ? min(offset, data.count - 1) : data.count + offset
        data[index] ^= 0x01
        let file = try Self.write(data, in: phone)
        let phoneForCheck = try BackupTestBed("byte")
        await #expect {
            try await phoneForCheck.service().check(file, passphrase: BackupTestBed.passphrase)
        } throws: { error in
            [BackupError.damaged, .wrongPassphrase, .notABackup].contains(error as? BackupError)
        }
        #expect(
            ((try? FileManager.default.contentsOfDirectory(atPath: phoneForCheck.location.staging.path)) ?? []).isEmpty)
    }

    @Test func aTruncatedFileFails() async throws {
        let (phone, data) = try await Self.demoExport()
        try await Self.expectRefused(try Self.write(data.prefix(data.count - 100), in: phone), .damaged)
        try await Self.expectRefused(try Self.write(data.prefix(data.count / 2), in: phone), .damaged)
    }

    @Test func anExtraByteAtTheEndFails() async throws {
        let (phone, data) = try await Self.demoExport()
        try await Self.expectRefused(try Self.write(data + Data([0]), in: phone), .damaged)
    }

    /// Two blocks of the encrypted body swapped: every byte is AEA's own, in the wrong order.
    @Test func reorderedBlocksFail() async throws {
        let (phone, original) = try await Self.demoExport()
        let block = 4_096
        let first = original.count / 3 / block * block
        let second = first + block
        guard second + block <= original.count else { return }
        var data = original
        data.replaceSubrange(first..<(first + block), with: original[second..<(second + block)])
        data.replaceSubrange(second..<(second + block), with: original[first..<(first + block)])
        try await Self.expectRefused(try Self.write(data, in: phone), .damaged)
    }

    @Test func aFileThatIsntACopyIsRefused() async throws {
        let phone = try BackupTestBed("not-a-copy")
        try await Self.expectRefused(try Self.write(Data("just some notes".utf8), in: phone), .notABackup)
        try await Self.expectRefused(try Self.write(Data(count: 10_000), in: phone), .notABackup)
    }

    /// A copy from a newer app, by its prologue: refused before the passphrase is even tried.
    @Test func aNewerFormatIsRefused() async throws {
        let phone = try BackupTestBed("newer")
        let url = phone.root.appending(path: "newer.nookbackup")
        try CraftedArchive.Prologue.write(url, authData: Data("NOOK-BACKUP 2".utf8))
        try await Self.expectRefused(url, passphrase: "anything at all here", .newerVersion)
    }

    /// A newer manifest or newer records inside a current prologue: refused too.
    @Test func newerContentsAreRefused() async throws {
        let phone = try BackupTestBed("newer-inside")
        let manifest = CraftedArchive.manifest(files: [:], formatVersion: 2)
        try await Self.expectRefused(
            try CraftedArchive.make(in: phone, manifest: manifest, entries: [CraftedArchive.Entry]()), .newerVersion)
        var records = CraftedArchive.manifest(files: [:])
        records.payloadVersion = 2
        try await Self.expectRefused(
            try CraftedArchive.make(in: phone, manifest: records, entries: [CraftedArchive.Entry]()), .newerVersion)
    }

    /// The export made by the first build with backups (format 1, payload 1), kept as a file:
    /// every later build must still restore it. Passphrase: "format version one fixture".
    @Test func theFormatOneFixtureRestores() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "format-1", withExtension: "nookbackup", subdirectory: "Fixtures"))
        let phone = try BackupTestBed("fixture-1")
        let service = phone.service()
        let preview = try await service.check(url, passphrase: "format version one fixture")
        #expect(preview.inCopy == BackupCounts(pieces: 3, looks: 1, suitcases: 1))
        #expect(preview.photos == 1 && preview.includesBodyData && preview.deletedForGood == 0)
        _ = try await service.restore(preview, as: .replace)
        phone.storage.reload()
        let garments = try await phone.storage.closet.garments()
        #expect(Set(garments.map(\.id)) == Set(BackupTestBed.demo.garments.prefix(3).map(\.id)))
        #expect(try await phone.storage.profile.profile().measurements.height == Length(160, .centimeters))
        #expect(
            try phone.rows().contains { $0.kind == "deletion" && $0.key == BackupTestBed.demo.garments[3].id.rawValue })
        #expect(phone.photos.ids() == ["5f0c2b1e-0000-4000-8000-000000000001"])
    }

    /// A copy built by hand from version 1 records restores.
    @Test func aHandBuiltFormatOneCopyRestores() async throws {
        let phone = try BackupTestBed("v1")
        let garments =
            Data(
                #"{"kind":"garment","records":[{"key":"g-1","value":"#.utf8)
            + (try RecordPayload.encode(
                Garment(id: "g-1", name: "Navy trousers", category: .bottom, addedAt: TestTime.now)))
            + Data("}]}".utf8)
        let manifest = CraftedArchive.manifest(
            files: ["records/garment.json": garments], counts: BackupCounts(pieces: 1))
        let file = try CraftedArchive.make(
            in: phone, manifest: manifest, entries: [("records/garment.json", garments)])
        let service = phone.service()
        let preview = try await service.check(file, passphrase: BackupTestBed.passphrase)
        #expect(preview.inCopy.pieces == 1)
        _ = try await service.restore(preview, as: .replace)
        phone.storage.reload()
        #expect(try await phone.storage.closet.garment("g-1").name == "Navy trousers")
    }
}
