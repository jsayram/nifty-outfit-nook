import Fixtures
import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

@testable import Services

/// One phone for the backup tests: its own store, photos, staging and exports under a temporary
/// folder, removed when the test lets go of it. A second test bed is a new phone, or the same
/// phone after the app was deleted.
final class BackupTestBed: Sendable {
    let root: URL
    let location: BackupLocation
    let storage: NookStorage
    let today: Date

    init(_ label: String = "phone", today: Date = TestTime.now) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "NookBackupTests", directoryHint: .isDirectory)
            .appending(path: "\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        location = .inside(root)
        self.today = today
        storage = try Self.open(location)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    static func open(_ location: BackupLocation) throws -> NookStorage {
        switch NookStorage.open(at: location.store, backups: location, calendar: TestTime.calendar) {
        case .ready(let storage): return storage
        case .problem(let problem): throw TemporaryStore.OpenFailure(problem: problem)
        }
    }

    /// The app opened again on the same folders, as at the next launch.
    func relaunch() throws -> NookStorage { try Self.open(location) }

    /// The backup service, at a fixed time and with as much free space as the test says.
    func service(now: Date? = nil, freeSpace: Int64? = nil) -> LocalBackupService {
        let date = now ?? today
        var space: (@Sendable () -> Int64)?
        if let freeSpace { space = { freeSpace } }
        return LocalBackupService(
            container: storage.container, location: location, now: { date }, calendar: TestTime.calendar,
            freeSpace: space)
    }

    func committer(now: Date? = nil) -> RestoreCommitter {
        let date = now ?? today
        return RestoreCommitter(container: storage.container, location: location, now: { date })
    }

    func rows() throws -> [StoreRow] { try StoreRow.all(in: ModelContext(storage.container)) }

    var photos: PhotoFiles { PhotoFiles(directory: location.photos) }

    // MARK: Her closet

    static let demo = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
    static let photoIDs = [
        "0b4f7a9e-1111-4c2a-9a51-photo00000001", "0b4f7a9e-2222-4c2a-9a51-photo00000002",
        "0b4f7a9e-3333-4c2a-9a51-photo00000003",
    ]

    /// The demo closet with real photo files: two pieces and the try-on photo point to stored
    /// photos. Also a draft, a look draft, the feedback note, measurements, onboarding finished
    /// and a tour seen, so every kind of record is there.
    func seedDemo() async throws {
        try BackupLocation.prepare(location.photos, backedUp: true)
        for (index, id) in Self.photoIDs.enumerated() {
            let bytes = Data((0..<(150_000 + index * 1_000)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ index) })
            try bytes.write(to: try #require(photos.url(for: id)))
        }
        var garments = Self.demo.garments
        garments[0].photo = .stored(EntityID(Self.photoIDs[0]))
        garments[1].photo = .stored(EntityID(Self.photoIDs[1]))
        for garment in garments { try await storage.closet.save(garment) }
        for look in Self.demo.looks { try await storage.looks.save(look) }
        for suitcase in Self.demo.suitcases { try await storage.suitcases.restore(suitcase) }
        for picture in Self.demo.pictures { try await storage.pictures.save(picture) }
        var profile = Self.demo.profile
        profile.tryOnPhoto = .stored(EntityID(Self.photoIDs[2]))
        profile.measurements.height = Length(160, .centimeters)
        try await storage.profile.save(profile)
        try await storage.drafts.save(
            GarmentDraft(
                target: .newPiece, step: .details, details: GarmentDetails(name: "Linen shirt"),
                base: GarmentDetails(), savedAt: today))
        try await storage.lookDrafts.save(LookDraft(name: "Friday", garmentIDs: [garments[2].id], savedAt: today))
        try await storage.feedbackDrafts.save(FeedbackDraft(message: "The hamper is lovely"))
        try await storage.onboarding.complete(startingCloset: .empty)
        try await storage.tours.setShowsTipsOnNewScreens(false)
    }

    /// `count` large-closet garments written in one save, quickly.
    func seedLarge(_ count: Int) throws {
        let large = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar).garments.prefix(count)
        try RecordTable<Garment>(kind: .garment).write(
            Dictionary(uniqueKeysWithValues: large.map { ($0.id.rawValue, $0) }), in: ModelContext(storage.container))
        storage.reload()
    }

    /// Exports with the service and saves the file outside the app's folders, as the Files sheet
    /// does, so clearing unsaved exports at launch leaves it alone.
    func export(passphrase: String = BackupTestBed.passphrase) async throws -> BackupFile {
        let file = try await service().export(passphrase: passphrase)
        let saved = root.appending(path: "Saved-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
        let url = saved.appending(path: file.name)
        try FileManager.default.moveItem(at: file.url, to: url)
        await service().discard(file)
        return BackupFile(url: url, bytes: file.bytes)
    }

    static let passphrase = "correct horse battery staple"
}

/// Every record of `kinds` in `lhs` and `rhs` holds the same value, field for field through its
/// value type, and neither has a record the other lacks.
func expectSameRecords(
    _ lhs: [StoreRow], _ rhs: [StoreRow], kinds: Set<String> = RecordCodec.restoredKinds,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let left = Dictionary(lhs.filter { kinds.contains($0.kind) }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let right = Dictionary(rhs.filter { kinds.contains($0.kind) }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let onlyLeft = Set(left.keys).subtracting(right.keys).sorted()
    let onlyRight = Set(right.keys).subtracting(left.keys).sorted()
    #expect(
        onlyLeft.isEmpty && onlyRight.isEmpty, "only left: \(onlyLeft), only right: \(onlyRight)",
        sourceLocation: sourceLocation)
    for (id, row) in left {
        guard let other = right[id], let codec = RecordCodec.byKind[row.kind] else { continue }
        #expect(codec.same(row, other), "\(id) differs", sourceLocation: sourceLocation)
    }
}

/// The SHA-256 of every photo file, by ID.
func photoHashes(_ photos: PhotoFiles) throws -> [String: String] {
    var hashes: [String: String] = [:]
    for id in photos.ids() {
        hashes[id] = BackupFormat.sha256(try Data(contentsOf: try #require(photos.url(for: id))))
    }
    return hashes
}
