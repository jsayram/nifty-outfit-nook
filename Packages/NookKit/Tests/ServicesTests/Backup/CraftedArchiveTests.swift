import AppleArchive
import Foundation
import Models
import NookTestSupport
import System
import Testing

@testable import Services

/// Archives built by hand, as an attacker would: correctly encrypted with the right passphrase,
/// but with paths, links, sizes or counts the app must refuse. Each stops the restore with
/// nothing written outside staging and staging cleared (THREAT_MODEL F4, 0004's test plan).
struct CraftedArchiveTests {
    private static let photo = Data("a photo".utf8)

    private static func refused(
        _ entries: [CraftedArchive.Entry], manifestFiles: [String: Data], limits: BackupLimits = BackupLimits(),
        freeSpace: Int64? = nil, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> BackupError? {
        let phone = try BackupTestBed("crafted")
        let manifest = CraftedArchive.manifest(files: manifestFiles)
        let file = try CraftedArchive.make(in: phone, manifest: manifest, entries: entries)
        var checker = RestoreChecker(location: phone.location)
        checker.reader.limits = limits
        if let freeSpace { checker.reader.freeSpace = { freeSpace } }
        let outside = phone.root.appending(path: "outside")
        defer {
            #expect(!FileManager.default.fileExists(atPath: outside.path), sourceLocation: sourceLocation)
            let staged = (try? FileManager.default.contentsOfDirectory(atPath: phone.location.staging.path)) ?? []
            #expect(staged.isEmpty, sourceLocation: sourceLocation)
        }
        do {
            _ = try checker.check(file, passphrase: BackupTestBed.passphrase)
            return nil
        } catch {
            return error
        }
    }

    @Test func aPathWithDotDotIsRefused() throws {
        let entries = [CraftedArchive.Entry(.regularFile, "photos/../../outside", Self.photo)]
        #expect(try Self.refused(entries, manifestFiles: [:]) == .damaged)
        #expect(try Self.refused(entries, manifestFiles: ["photos/../../outside": Self.photo]) == .damaged)
    }

    @Test func anAbsolutePathIsRefused() throws {
        let entries = [CraftedArchive.Entry(.regularFile, "/tmp/outside", Self.photo)]
        #expect(try Self.refused(entries, manifestFiles: ["/tmp/outside": Self.photo]) == .damaged)
    }

    @Test func aLinkIsRefused() throws {
        let entries = [CraftedArchive.Entry(.link, "photos/link", nil)]
        #expect(try Self.refused(entries, manifestFiles: ["photos/link": Data()]) == .damaged)
    }

    @Test func tooManyEntriesAreRefused() throws {
        var limits = BackupLimits()
        limits.maximumEntries = 50
        let entries = (0..<60).map { _ in CraftedArchive.Entry(.directory, "photos", nil) }
        #expect(try Self.refused(entries, manifestFiles: [:], limits: limits) == .damaged)
        #expect(BackupLimits().maximumEntries == 200_000)
    }

    @Test func aFileBiggerThanTheManifestSaysIsRefused() throws {
        let entries = [CraftedArchive.Entry(.regularFile, "photos/abc", Self.photo + Self.photo)]
        #expect(try Self.refused(entries, manifestFiles: ["photos/abc": Self.photo]) == .damaged)
    }

    @Test func aFileTheManifestDoesntListIsRefused() throws {
        let entries = [CraftedArchive.Entry(.regularFile, "photos/abc", Self.photo)]
        #expect(try Self.refused(entries, manifestFiles: [:]) == .damaged)
    }

    @Test func aFileTheManifestListsButIsMissingIsRefused() throws {
        #expect(try Self.refused([CraftedArchive.Entry](), manifestFiles: ["photos/abc": Self.photo]) == .damaged)
    }

    @Test func aChangedFileIsRefused() throws {
        let entries = [CraftedArchive.Entry(.regularFile, "photos/abc", Data("a phot0".utf8))]
        #expect(try Self.refused(entries, manifestFiles: ["photos/abc": Self.photo]) == .damaged)
    }

    @Test func aCopyBiggerThanTheFreeSpaceIsRefused() throws {
        let entries = [CraftedArchive.Entry(.regularFile, "photos/abc", Self.photo)]
        let error = try Self.refused(entries, manifestFiles: ["photos/abc": Self.photo], freeSpace: 1_000)
        guard case .notEnoughSpace = error else {
            Issue.record("expected notEnoughSpace, got \(String(describing: error))")
            return
        }
    }

    /// 32b: sizes in the manifest that overflow when added used to trap (the app ended) before
    /// any file was read. Now the copy is damaged, and nothing is staged.
    @Test func manifestSizesThatOverflowAreRefused() throws {
        let hash = BackupFormat.sha256(Self.photo)
        for files in [
            [
                "photos/a": BackupManifest.File(size: .max / 2 + 1, sha256: hash),
                "photos/b": .init(size: .max / 2 + 1, sha256: hash),
            ],
            ["photos/a": BackupManifest.File(size: .max - 10, sha256: hash)],
        ] {
            let phone = try BackupTestBed("crafted-overflow")
            var manifest = CraftedArchive.manifest(files: [:])
            manifest.files = files
            let file = try CraftedArchive.make(
                in: phone, manifest: manifest, entries: [CraftedArchive.Entry(.regularFile, "photos/a", Self.photo)])
            let checker = RestoreChecker(location: phone.location)
            #expect(throws: BackupError.damaged) { _ = try checker.check(file, passphrase: BackupTestBed.passphrase) }
            let staged = (try? FileManager.default.contentsOfDirectory(atPath: phone.location.staging.path)) ?? []
            #expect(staged.isEmpty)
        }
    }

    @Test func aRecordThatFailsItsChecksIsRefused() throws {
        // A garment whose key isn't its ID, and one whose name breaks the rules.
        let garment = try RecordPayload.encode(
            Garment(id: "g-1", name: "Tee", category: .top, addedAt: TestTime.now))
        let wrongKey = Data(#"{"kind":"garment","records":[{"key":"g-2","value":"#.utf8) + garment + Data("}]}".utf8)
        #expect(
            try Self.refused(
                [.init(.regularFile, "records/garment.json", wrongKey)],
                manifestFiles: ["records/garment.json": wrongKey]) == .damaged)
        let long = try RecordPayload.encode(
            Garment(id: "g-1", name: String(repeating: "a", count: 5_000), category: .top, addedAt: TestTime.now))
        let badName = Data(#"{"kind":"garment","records":[{"key":"g-1","value":"#.utf8) + long + Data("}]}".utf8)
        #expect(
            try Self.refused(
                [.init(.regularFile, "records/garment.json", badName)],
                manifestFiles: ["records/garment.json": badName]) == .damaged)
    }

    @Test func safePaths() {
        #expect(BackupFormat.isSafePath("records/garment.json"))
        #expect(BackupFormat.isSafePath("photos/0b4f7a9e-1111"))
        for path in ["", "/abs", "a/../b", "..", "a//b", ".hidden", "photos/.x", "a\\b", "photos/é", "a/b/"] {
            #expect(!BackupFormat.isSafePath(path), "\(path)")
        }
    }
}

/// Builds archives entry by entry with the app's own writer, for the tests.
enum CraftedArchive {
    struct Entry {
        var type: ArchiveHeader.EntryType
        var path: String
        var data: Data?

        init(_ type: ArchiveHeader.EntryType, _ path: String, _ data: Data?) {
            self.type = type
            self.path = path
            self.data = data
        }
    }

    static func manifest(
        files: [String: Data], counts: BackupCounts = BackupCounts(), formatVersion: Int = BackupFormat.formatVersion
    ) -> BackupManifest {
        BackupManifest(
            formatVersion: formatVersion, kind: .records, payloadVersion: 1, storeVersion: 1, appVersion: "1.0",
            appBuild: "1", createdAt: TestTime.now, counts: counts, includesBodyData: false, includesTryOnPhoto: false,
            files: files.mapValues { .init(size: Int64($0.count), sha256: BackupFormat.sha256($0)) })
    }

    /// A copy with this manifest first, then these entries.
    static func make(in phone: BackupTestBed, manifest: BackupManifest, entries: [(String, Data)]) throws -> URL {
        try make(in: phone, manifest: manifest, entries: entries.map { Entry(.regularFile, $0.0, $0.1) })
    }

    static func make(in phone: BackupTestBed, manifest: BackupManifest, entries: [Entry]) throws -> URL {
        let url = phone.root.appending(path: "crafted-\(UUID().uuidString).nookbackup")
        try FileManager.default.createDirectory(at: phone.root, withIntermediateDirectories: true)
        let writer = try BackupArchiveWriter(url: url, passphrase: BackupTestBed.passphrase)
        try writer.add(path: BackupFormat.manifestPath, data: BackupManifest.encoder().encode(manifest))
        for entry in entries {
            try writer.addRaw(type: entry.type, path: entry.path, data: entry.data)
        }
        try writer.finish()
        return url
    }

    /// An empty archive with a prologue of our choosing.
    final class Prologue {
        static func write(_ url: URL, authData: Data) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let context = ArchiveEncryptionContext(
                profile: .hkdf_sha256_aesctr_hmac__scrypt__none, compressionAlgorithm: .lzfse)
            context.authData = authData
            try context.setPassword(BackupTestBed.passphrase)
            let file = try #require(
                ArchiveByteStream.fileStream(
                    path: FilePath(url.path), mode: .writeOnly, options: [.create, .truncate],
                    permissions: [.ownerReadWrite]))
            let encryption = try #require(
                ArchiveByteStream.encryptionStream(writingTo: file, encryptionContext: context))
            try encryption.close()
            try file.close()
        }
    }
}
