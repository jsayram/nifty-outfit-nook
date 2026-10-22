import Fixtures
import Foundation
import Models
import NookTestSupport
import SwiftData
import Synchronization
import Testing

@testable import Services

/// Phase 32a: the real store (SwiftData on a store file of its own) holding 5,000 pieces, 3,000
/// looks and 500 try-on pictures (`ScaleData`). What the app does with her data at launch and when
/// she backs up: open the store, read everything the screens read, sweep for files nothing points
/// to, summarise and export.
///
/// Every check prints a "SCALE" line (see ScaleBrowsingTests); the numbers are in
/// LOAD_TEST_REPORT.md in the closet repo. The bounds are loose and are only there to catch a
/// change that makes something many times slower.
///
/// The photo part is heavy (it writes the photos a closet this size would have) and only runs when
/// asked: `TEST_RUNNER_NOOK_PERFORMANCE=1`, with `TEST_RUNNER_NOOK_SCALE_PHOTOS=<count>` photos
/// (default 400; each is 1.8 MB of random bytes, as an iPhone 12's JPEG compresses to), and
/// `TEST_RUNNER_NOOK_SCALE_ALL_PIECES=1` to write all 5,000 pieces' records beside them (slow).
/// It exists because the first run of it found the export holding every photo in memory at once
/// (1,789 MB peak for 1,000 photos); `BackupArchiveWriter.add` now reads each piece in its own
/// autorelease pool, and the same run peaks at about 100 MB.
@Suite(.serialized)
struct ScaleStoreTests {
    private static let data = ScaleData.make(
        growing: FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar).garments, now: TestTime.now)

    private static let heavy = ProcessInfo.processInfo.environment["NOOK_PERFORMANCE"] == "1"

    private func limit(_ milliseconds: Double) -> Double { SpeedCheck.isOnCI ? milliseconds * 3 : milliseconds }

    private func fixed(_ value: Double, _ digits: Int = 1) -> String { ScaleReport.fixed(value, digits) }

    /// A folder for one phone, removed when the test is done.
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "NookScaleTests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    /// Writes the scale data into the store as new rows in one save. (`RecordTable.write` looks
    /// every key up first, and that took 57 s for these 8,500 records; nothing in the app writes
    /// this many at once, and a restore doesn't either.)
    private func seed(_ storage: NookStorage, garments: [Garment]) throws {
        let started = ContinuousClock.now
        let context = ModelContext(storage.container)
        let now = Date()
        func add<Value: Codable & Sendable>(_ kind: RecordKind, _ key: String, _ value: Value) throws {
            context.insert(
                StoredRecord(
                    kind: kind.rawValue, key: key, payloadVersion: RecordPayload.currentVersion,
                    payload: try RecordPayload.encode(value), savedAt: now))
        }
        for garment in garments { try add(.garment, garment.id.rawValue, garment) }
        for look in Self.data.looks { try add(.look, look.id.rawValue, look) }
        for picture in Self.data.pictures { try add(.picture, picture.id.rawValue, picture) }
        try context.save()
        storage.reload()
        let seconds = ScaleReport.milliseconds(ContinuousClock.now - started) / 1_000
        let counts = "\(garments.count) pieces, \(Self.data.looks.count) looks, \(Self.data.pictures.count) pictures"
        ScaleReport.note("Writing \(counts) to the store as new rows in one save: \(fixed(seconds)) s")
    }

    /// The footprint's highest value while `work` runs, sampled every 10 ms.
    private func peakFootprint(during work: () async throws -> Void) async rethrows -> Double {
        let peak = Mutex(ScaleReport.footprintMB())
        let sampler = Task.detached {
            while !Task.isCancelled {
                let now = ScaleReport.footprintMB()
                peak.withLock { $0 = max($0, now) }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        defer { sampler.cancel() }
        try await work()
        return peak.withLock { $0 }
    }

    // MARK: Launch

    @Test func launchWithTheScaleCloset() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = BackupLocation.inside(root)
        do {
            // The phone's first run: opens, is seeded, and is let go, so each open below is a launch.
            let first = try BackupTestBed.open(location)
            try seed(first, garments: Self.data.garments)
        }
        let launches = try ScaleReport.measure("Launch: the store opens, 5,000 + 3,000 + 500 records", runs: 3) {
            _ = try BackupTestBed.open(location)
        }
        #expect(launches.fastest < limit(5_000))

        // Cold: a fresh store object each time, so nothing is kept from the run before. This is
        // what the first screens wait for after a launch (the stores keep what they read).
        var counts = (pieces: 0, looks: 0, pictures: 0)
        let cold = try await ScaleReport.measure("Launch: open and read every record, cold", runs: 3) {
            let fresh = try BackupTestBed.open(location)
            async let pieceList = fresh.closet.garments()
            async let lookList = fresh.looks.looks()
            async let pictureList = fresh.pictures.pictures()
            counts = try await (pieceList.count, lookList.count, pictureList.count)
        }
        #expect(counts.pieces == 5_000 && counts.looks == 3_000 && counts.pictures == 500)
        #expect(cold.fastest < limit(8_000))

        let storage = try BackupTestBed.open(location)
        _ = try await storage.closet.garments()
        _ = try await storage.looks.looks()

        // What a tab does when it appears, once the stores have what they read.
        let closet = try await ScaleReport.measure("A screen reads all 5,000 pieces", runs: 5) {
            _ = try await storage.closet.garments()
        }
        let saved = try await ScaleReport.measure("A screen reads all 3,000 looks", runs: 5) {
            _ = try await storage.looks.looks()
        }
        #expect(closet.fastest < limit(3_000) && saved.fastest < limit(3_000))

        // One edit, as she makes it: a save writes one record through the store's own check.
        let edited = Self.data.garments[100]
        var counter = 0
        let saveOne = try await ScaleReport.measure("One edit saved, among 5,000 pieces", runs: 10) {
            counter += 1
            let name = "Edited piece \(counter)"
            try await storage.closet.update(edited.id) { $0.name = name }
        }
        let aLook = Self.data.looks[10]
        let saveLook = try await ScaleReport.measure("One look saved, among 3,000 looks", runs: 10) {
            try await storage.looks.save(aLook)
        }
        #expect(saveOne.fastest < limit(500) && saveLook.fastest < limit(500))

        // The sweep for files nothing points to, away from the screens a moment after launch.
        let sweep = await ScaleReport.measure("Launch sweep for unused photo files (reads every record)", runs: 3) {
            await storage.imageFiles?.removeUnused()
        }
        #expect(sweep.fastest < limit(5_000))
    }

    // MARK: Backup

    @Test func backupExportWithTheScaleCloset() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try BackupTestBed.open(.inside(root))
        try seed(storage, garments: Self.data.garments)
        let service = try #require(storage.backups)

        var summary: BackupSummary?
        let summarised = try await ScaleReport.measure("Backup: the summary Export shows first", runs: 3) {
            summary = try await service.summary()
        }
        ScaleReport.note(
            "Backup summary: \(summary?.counts.pieces ?? 0) pieces, \(summary?.photos ?? 0) photos, about \(summary?.estimatedBytes ?? 0) bytes"
        )
        #expect(summarised.fastest < limit(5_000))

        var file: BackupFile?
        var peak = 0.0
        let before = ScaleReport.footprintMB()
        let exported = try await ScaleReport.measure("Backup: export, records only (no photo files)", runs: 3) {
            if let file { await service.discard(file) }
            let passphrase = service.makePassphrase()
            peak = max(peak, try await peakFootprint { file = try await service.export(passphrase: passphrase) })
        }
        let size = file?.bytes ?? 0
        let megabytes = Double(size) / 1_048_576
        ScaleReport.note(
            "Backup export, records only: \(fixed(megabytes, 2)) MB file, memory \(fixed(before, 0)) MB before, peak \(fixed(peak, 0)) MB"
        )
        #expect(exported.fastest < limit(15_000))
        #expect(size > 0)
        if let file { await service.discard(file) }
    }

    @Test(.enabled(if: heavy))
    func backupExportWithPhotos() async throws {
        let count = Int(ProcessInfo.processInfo.environment["NOOK_SCALE_PHOTOS"] ?? "") ?? 400
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = BackupLocation.inside(root)
        let storage = try BackupTestBed.open(location)
        try BackupLocation.prepare(location.photos, backedUp: true)
        let photos = PhotoFiles(directory: location.photos)
        var garments = Self.data.garments
        // One 1.8 MB file of random bytes per piece, for the first `count` pieces. Random bytes
        // don't compress, as a JPEG doesn't, so the archive is about as big as the photos.
        var bytes = Data(count: 1_800_000)
        for index in 0..<count {
            bytes.withUnsafeMutableBytes { buffer in
                var state = UInt64(index + 1) &* 0x9E37_79B9_7F4A_7C15
                for offset in stride(from: 0, to: buffer.count - 8, by: 8) {
                    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    buffer.storeBytes(of: state, toByteOffset: offset, as: UInt64.self)
                }
            }
            let id = UUID().uuidString.lowercased()
            try bytes.write(to: try #require(photos.url(for: id)))
            garments[index].photo = .stored(EntityID(id))
        }
        // The records are a few megabytes next to the photos, so only the pieces with photos and a
        // few more are written; seeding all 5,000 takes minutes and adds nothing here.
        let everyPiece = ProcessInfo.processInfo.environment["NOOK_SCALE_ALL_PIECES"] == "1"
        try seed(storage, garments: everyPiece ? garments : Array(garments.prefix(count + 200)))
        let service = try #require(storage.backups)

        var file: BackupFile?
        let before = ScaleReport.footprintMB()
        let clock = ContinuousClock()
        let start = clock.now
        let passphrase = service.makePassphrase()
        let peak = try await peakFootprint { file = try await service.export(passphrase: passphrase) }
        let seconds = ScaleReport.milliseconds(clock.now - start) / 1_000
        let megabytes = Double(file?.bytes ?? 0) / 1_048_576
        ScaleReport.note(
            "Backup export with \(count) photos of 1.8 MB: \(fixed(seconds)) s, \(fixed(megabytes, 0)) MB file (\(fixed(megabytes / seconds, 0)) MB/s), memory \(fixed(before, 0)) MB before, peak \(fixed(peak, 0)) MB"
        )
        guard let file else { return }

        // Checking the copy is the first half of a restore: it decrypts everything into staging.
        var preview: BackupPreview?
        let checkStart = clock.now
        let beforeCheck = ScaleReport.footprintMB()
        let checkPeak = try await peakFootprint { preview = try await service.check(file.url, passphrase: passphrase) }
        let checkSeconds = ScaleReport.milliseconds(clock.now - checkStart) / 1_000
        ScaleReport.note(
            "Check a copy with \(count) photos: \(fixed(checkSeconds)) s, memory \(fixed(beforeCheck, 0)) MB before, peak \(fixed(checkPeak, 0)) MB"
        )

        // The second half: a safety copy of the closet as it is, then every record in one save.
        let restoreStart = clock.now
        let beforeRestore = ScaleReport.footprintMB()
        let ready = try #require(preview)
        let restorePeak = try await peakFootprint { _ = try await service.restore(ready, as: .replace) }
        let restoreSeconds = ScaleReport.milliseconds(clock.now - restoreStart) / 1_000
        ScaleReport.note(
            "Restore (Replace) of that copy: \(fixed(restoreSeconds)) s, memory \(fixed(beforeRestore, 0)) MB before, peak \(fixed(restorePeak, 0)) MB"
        )
        await service.discardChecked()
        await service.discard(file)
    }
}
