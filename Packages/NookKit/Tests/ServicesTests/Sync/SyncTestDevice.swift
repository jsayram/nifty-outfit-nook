import Fixtures
import Foundation
import Models
import NookTestSupport
import SwiftData
import Synchronization
import Testing

@testable import Services

/// One simulated iPhone or iPad for the sync tests: its own store and photos under a temporary
/// folder, its own iCloud sign-in, and `ICloudSync` on the stand-in engine. The clock is fixed.
final class SyncTestDevice: Sendable {
    let root: URL
    let location: BackupLocation
    let storage: NookStorage
    let sync: ICloudSync
    let account: FakeICloudAccount
    let server: FakeCloudKit
    let knownPayloadVersion: Int?
    let marker: FakeDeviceMarker

    init(
        _ label: String, server: FakeCloudKit, account: String? = "lily", knownPayloadVersion: Int? = nil,
        root: URL? = nil, signIn: FakeICloudAccount? = nil, marker: FakeDeviceMarker = FakeDeviceMarker()
    ) throws {
        self.marker = marker
        self.root =
            root
            ?? FileManager.default.temporaryDirectory
            .appending(path: "NookSyncTests", directoryHint: .isDirectory)
            .appending(path: "\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        location = .inside(self.root)
        self.server = server
        self.account = signIn ?? FakeICloudAccount(account)
        self.knownPayloadVersion = knownPayloadVersion
        let storage = try BackupTestBed.open(location)
        self.storage = storage
        let location = location
        sync = ICloudSync(
            storage: storage, location: location,
            engine: FakeSyncEngine.maker(server: server, account: self.account),
            now: { TestTime.now }, knownPayloadVersion: knownPayloadVersion, deviceMarker: marker,
            eraseThisDevice: {
                let report = await LocalDataDeletion(stores: storage.erasableData).delete(.thisDevice)
                return report.isComplete
            })
    }

    /// The app opened again on the same folders, as at the next launch (or after an update).
    func relaunch(knownPayloadVersion: Int? = nil) throws -> SyncTestDevice {
        try SyncTestDevice(
            "relaunch", server: server, knownPayloadVersion: knownPayloadVersion ?? self.knownPayloadVersion,
            root: root, signIn: account, marker: marker)
    }

    /// This device's store and photos restored onto a new device from a device backup: the same
    /// files, but a Keychain that never held this device's marker.
    func restoredOntoNewDevice() throws -> SyncTestDevice {
        let newRoot = root.deletingLastPathComponent().appending(path: "restored-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: root, to: newRoot)
        return try SyncTestDevice("restored", server: server, root: newRoot, signIn: account)
    }

    func removeFolder() { try? FileManager.default.removeItem(at: root) }

    // MARK: Her closet

    var photos: PhotoFiles { PhotoFiles(directory: location.photos) }

    func garments() async throws -> [Garment] { try await storage.closet.garments() }

    func garment(_ id: Garment.ID) async throws -> Garment? {
        try await garments().first { $0.id == id }
    }

    /// A piece, with a stored photo of `photoBytes` bytes when asked.
    @discardableResult
    func addPiece(_ name: String, photoBytes: Int? = nil, index: Int = 0) async throws -> Garment {
        var garment = BackupTestBed.demo.garments[index]
        garment = Garment(
            id: Garment.ID(UUID().uuidString), name: name, category: garment.category, colors: garment.colors,
            photo: .noPhoto, addedAt: TestTime.now)
        if let photoBytes {
            let photoID = UUID().uuidString
            try BackupLocation.prepare(location.photos, backedUp: true)
            let bytes = Data((0..<photoBytes).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ photoBytes) })
            try bytes.write(to: try #require(photos.url(for: photoID)))
            garment.photo = .stored(EntityID(photoID))
        }
        try await storage.closet.save(garment)
        return garment
    }

    func rename(_ id: Garment.ID, _ name: String) async throws {
        try await storage.closet.update(id) { $0.name = name }
    }

    func rows(_ kind: RecordKind) throws -> [StoreRow] {
        try StoreRow.all(in: ModelContext(storage.container)).filter { $0.kind == kind.rawValue }
    }

    func conflicts() throws -> [StoredSyncConflict] {
        SyncBook(context: ModelContext(storage.container)).conflicts().values.sorted { $0.key < $1.key }
    }

    func status() async -> ICloudSyncStatus { await sync.status() }
}

/// The Keychain marker of one simulated device.
final class FakeDeviceMarker: SyncDeviceMarker {
    private let value = Mutex<String?>(nil)
    func read() -> String? { value.withLock { $0 } }
    func write(_ marker: String) { value.withLock { $0 = marker } }
}

/// Two devices on one account and the stand-in server, cleaned up afterwards.
struct SyncPair {
    let server = FakeCloudKit()
    let phone: SyncTestDevice
    let iPad: SyncTestDevice

    init(account: String = "lily") throws {
        phone = try SyncTestDevice("phone", server: server, account: account)
        iPad = try SyncTestDevice("ipad", server: server, account: account)
    }

    /// Both devices with sync on, the phone first.
    func turnOnBoth() async {
        #expect(await phone.sync.turnOn() == .on)
        #expect(await iPad.sync.turnOn() == .on)
    }

    func cleanUp() {
        phone.removeFolder()
        iPad.removeFolder()
    }
}
