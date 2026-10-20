import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// Phase 21b's checkpoint, in code: export a closet, delete the app, restore it, and every record
/// and photo is back (0004's test plan, "Export format", round trip).
struct BackupRoundTripTests {
    /// The demo closet with photos, drafts, measurements and every other kind of record: exported,
    /// restored on a new phone with Replace, field for field and hash for hash.
    @Test func theDemoClosetComesBackWhole() async throws {
        let phone = try BackupTestBed("old-phone")
        try await phone.seedDemo()
        let file = try await phone.export()

        let newPhone = try BackupTestBed("new-phone")
        let service = newPhone.service()
        let preview = try await service.check(file.url, passphrase: BackupTestBed.passphrase)
        #expect(preview.inCopy.pieces == BackupTestBed.demo.garments.filter { !$0.isDeleted }.count)
        #expect(preview.inCopy.looks == BackupTestBed.demo.looks.count)
        #expect(preview.inCopy.drafts == 3)
        #expect(preview.onPhone.isEmpty)
        #expect(preview.photos == 3)
        #expect(preview.includesBodyData && preview.includesTryOnPhoto)
        #expect(preview.createdAt == phone.today)

        let outcome = try await service.restore(preview, as: .replace)
        #expect(outcome.counts == preview.inCopy)
        expectSameRecords(try newPhone.rows(), try phone.rows())
        #expect(try photoHashes(newPhone.photos) == (try photoHashes(phone.photos)))

        // And through the app's own stores, on fresh actors, as the screens see it.
        newPhone.storage.reload()
        let restored = Set(try await newPhone.storage.closet.garments())
        #expect(restored == Set(try await phone.storage.closet.garments()))
        #expect(try await newPhone.storage.profile.profile() == (try await phone.storage.profile.profile()))
        #expect(try await newPhone.storage.onboarding.state().isCompleted)
        #expect(try await newPhone.storage.feedbackDrafts.draft() == (try await phone.storage.feedbackDrafts.draft()))
    }

    /// 2,400 pieces, the large closet, round trip.
    @Test func theLargeClosetComesBackWhole() async throws {
        let phone = try BackupTestBed("large")
        try phone.seedLarge(2_400)
        let file = try await phone.export()
        let newPhone = try BackupTestBed("large-new")
        let service = newPhone.service()
        let preview = try await service.check(file.url, passphrase: BackupTestBed.passphrase)
        #expect(preview.inCopy.pieces + preview.inCopy.recentlyDeleted == 2_400)
        _ = try await service.restore(preview, as: .replace)
        expectSameRecords(try newPhone.rows(), try phone.rows(), kinds: [RecordKind.garment.rawValue])
    }

    /// An empty closet exports and restores to an empty closet, with onboarding finished.
    @Test func anEmptyClosetRoundTrips() async throws {
        let phone = try BackupTestBed("empty")
        let file = try await phone.export()
        let newPhone = try BackupTestBed("empty-new")
        let service = newPhone.service()
        let preview = try await service.check(file.url, passphrase: BackupTestBed.passphrase)
        #expect(preview.inCopy.isEmpty)
        let outcome = try await service.restore(preview, as: .replace)
        #expect(outcome.counts.isEmpty)
        newPhone.storage.reload()
        #expect(try await newPhone.storage.onboarding.state().isCompleted)
    }

    /// The file's name is the date only, and its clear prologue only the format marker. None of
    /// the demo's words appear anywhere in the file's bytes.
    @Test func nothingAboutHerIsInTheClear() async throws {
        let phone = try BackupTestBed("clear")
        try await phone.seedDemo()
        let file = try await phone.export()
        #expect(file.name == "Nifty Outfit Nook 2026-10-14.nookbackup")
        let bytes = try Data(contentsOf: file.url)
        #expect(bytes.range(of: Data("NOOK-BACKUP 1".utf8)) != nil)
        let names = BackupTestBed.demo.garments.prefix(10).map(\.name) + ["Linen shirt", "The hamper is lovely"]
        for name in names {
            #expect(bytes.range(of: Data(name.utf8)) == nil, "\(name) is readable in the file")
        }
    }

    /// The archive holds the manifest, one file per kind and the photos the records point to:
    /// no `UserDefaults` marker, no sync state, no caches, and no purged piece.
    @Test func whatsLeftOutStaysOut() async throws {
        let phone = try BackupTestBed("left-out")
        try await phone.seedDemo()
        let purged = BackupTestBed.demo.garments[3].id
        try await phone.storage.closet.delete(purged, at: TestTime.day(-1))
        try await phone.storage.closet.deletePermanently(purged)
        let unreferenced = try #require(phone.photos.url(for: "0b4f7a9e-9999-4c2a-9a51-orphan000001"))
        try Data("orphan".utf8).write(to: unreferenced)
        let file = try await phone.export()

        let staging = phone.root.appending(path: "Inspect", directoryHint: .isDirectory)
        try BackupLocation.prepare(staging)
        let manifest = try BackupArchiveReader().extract(file.url, passphrase: BackupTestBed.passphrase, into: staging)
        let paths = Set(manifest.files.keys)
        #expect(paths.allSatisfy { $0.hasPrefix("records/") || $0.hasPrefix("photos/") })
        #expect(!paths.contains("records/defaultsImport.json"))
        #expect(paths.contains("records/deletion.json"))
        #expect(!paths.contains("photos/0b4f7a9e-9999-4c2a-9a51-orphan000001"))
        let garments = try String(contentsOf: staging.appending(path: "records/garment.json"), encoding: .utf8)
        #expect(!garments.contains("\"\(purged.rawValue)\""))
        #expect(manifest.kind == .records && manifest.formatVersion == 1 && manifest.payloadVersion == 1)
    }

    /// The passphrase is never written anywhere: not in the export's folder, the store, its journal
    /// or the staging folder, before or after a restore.
    @Test func thePassphraseIsNeverWritten() async throws {
        let phone = try BackupTestBed("passphrase")
        try await phone.seedDemo()
        let passphrase = "a passphrase only I know 4821"
        let file = try await phone.export(passphrase: passphrase)
        let service = phone.service()
        let preview = try await service.check(file.url, passphrase: passphrase)
        _ = try await service.restore(preview, as: .addMissing)
        let files = FileManager.default.enumerator(at: phone.root, includingPropertiesForKeys: nil)
        var checked = 0
        while let url = files?.nextObject() as? URL {
            guard let data = try? Data(contentsOf: url) else { continue }
            checked += 1
            #expect(data.range(of: Data(passphrase.utf8)) == nil, "the passphrase is in \(url.lastPathComponent)")
        }
        #expect(checked > 3)
    }

    /// A generated passphrase: 24 symbols from the stated alphabet, in six groups of four.
    @Test func aGeneratedPassphraseHasTheStatedShape() throws {
        let passphrase = BackupPassphraseMaker.make()
        let groups = passphrase.split(separator: "-")
        #expect(groups.count == 6 && groups.allSatisfy { $0.count == 4 })
        #expect(passphrase.replacingOccurrences(of: "-", with: "").allSatisfy(BackupPassphrase.alphabet.contains))
        #expect(BackupPassphraseMaker.make() != passphrase)
    }

    /// A store copy from the recovery screen opens through the migration coordinator in staging
    /// (here the app's own plan, so no schema change), then restores with every record and photo.
    /// A copy from an older schema migrates there the same way; that can't run beside the other
    /// suites until the app has a real second schema, because a test-only version 2 opened in the
    /// same process makes SwiftData map the shared model to it (the 20a gotcha).
    @Test func aStoreCopyRestoresThroughTheCoordinator() async throws {
        let phone = try BackupTestBed("store-copy")
        try await phone.seedDemo()
        let file = try await StoreCopyExport(location: phone.location)
            .exportStoreCopy(passphrase: BackupTestBed.passphrase)

        let newPhone = try BackupTestBed("store-copy-new")
        let checker = RestoreChecker(location: newPhone.location)
        let copy = try checker.check(file.url, passphrase: BackupTestBed.passphrase)
        #expect(copy.manifest.kind == .storeCopy)
        #expect(copy.manifest.files[BackupFormat.storePath] != nil)
        _ = try newPhone.committer().restore(copy, as: .replace)
        expectSameRecords(try newPhone.rows(), try phone.rows())
        #expect(try photoHashes(newPhone.photos) == (try photoHashes(phone.photos)))
    }

    /// Exporting with too little space stops before anything is written, and says how much is
    /// needed.
    @Test func exportingWithoutSpaceStopsFirst() async throws {
        let phone = try BackupTestBed("export-space")
        try await phone.seedDemo()
        await #expect {
            try await phone.service(freeSpace: 1_000).export(passphrase: BackupTestBed.passphrase)
        } throws: { error in
            guard case BackupError.notEnoughSpace(let needed) = error else { return false }
            return needed > 450_000
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: phone.location.exports.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    /// A passphrase shorter than 12 characters isn't accepted.
    @Test func aShortPassphraseIsRefused() async throws {
        let phone = try BackupTestBed("short")
        await #expect(throws: BackupError.passphrase(.tooShort)) {
            try await phone.service().export(passphrase: "too short")
        }
    }
}
