import CloudKit
import Foundation
import Synchronization

// The real engine: a thin wrapper over `CKSyncEngine` (iOS 17+), turning its events and records
// into the app's `SyncEvent` and `SyncRecord`. All the decisions are in `ICloudSync`, tested
// against a stand-in; this file only translates. It runs once the iCloud container exists and
// the build is made with `NOOK_ICLOUD = YES` (docs/icloud.md). APIs checked against the iOS 27.1
// SDK's CloudKit interface and Apple's documentation on 22 October 2026.

/// A `SyncRecord` as a `CKRecord` and back (0004 "Which fields are encrypted").
///
/// Only the record name (a random ID), the record type and CloudKit's system fields are plain.
/// Everything about her is in `encryptedValues`: the payload, its version, and the tombstone
/// flag. An image is a `CKAsset`, which CloudKit encrypts by default with its key in an
/// encrypted field. No `CKRecord.Reference`: references can't be encrypted, so relationships
/// live inside the payload.
enum CloudKitRecordMapping {
    static let payloadKey = "payload"
    static let versionKey = "payloadVersion"
    static let tombstoneKey = "tombstone"
    static let assetKey = "asset"

    static func zoneID(_ zone: SyncZone) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zone.rawValue, ownerName: CKCurrentUserDefaultName)
    }

    static func zone(_ id: CKRecordZone.ID) -> SyncZone? { SyncZone(rawValue: id.zoneName) }

    static func recordID(_ id: SyncRecordID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.name, zoneID: zoneID(id.zone))
    }

    static func syncID(_ id: CKRecord.ID) -> SyncRecordID? {
        zone(id.zoneID).map { SyncRecordID(zone: $0, name: id.recordName) }
    }

    /// The record to save: rebuilt from its system fields when the server has seen it, so the
    /// save says which version it's based on.
    static func ckRecord(_ record: SyncRecord) -> CKRecord {
        let ck =
            record.systemFields.flatMap(decodeSystemFields)
            ?? CKRecord(recordType: record.type.rawValue, recordID: recordID(record.id))
        if record.type == .image {
            ck[assetKey] = record.asset.map { CKAsset(fileURL: $0) }
            return ck
        }
        ck.encryptedValues[payloadKey] = record.payload.map { $0 as NSData }
        ck.encryptedValues[versionKey] = record.payloadVersion as NSNumber
        ck.encryptedValues[tombstoneKey] = (record.isTombstone ? 1 : 0) as NSNumber
        return ck
    }

    static func syncRecord(_ ck: CKRecord) -> SyncRecord? {
        guard let id = syncID(ck.recordID), let type = SyncRecordType(rawValue: ck.recordType) else { return nil }
        var record = SyncRecord(
            id: id, type: type, systemFields: encodeSystemFields(ck), changeTag: ck.recordChangeTag)
        if type == .image {
            record.asset = (ck[assetKey] as? CKAsset)?.fileURL
        } else {
            record.payload = ck.encryptedValues[payloadKey] as? Data
            record.payloadVersion = (ck.encryptedValues[versionKey] as? Int) ?? 0
            record.isTombstone = (ck.encryptedValues[tombstoneKey] as? Int) == 1
        }
        return record
    }

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// The `CKError` codes the app acts on (Apple's CKSyncEngine sample and 0004's table).
    static func failure(_ error: CKError) -> SyncFailure {
        switch error.code {
        case .serverRecordChanged: .serverRecordChanged(error.serverRecord.flatMap(syncRecord))
        case .quotaExceeded: .quotaExceeded
        case .zoneNotFound:
            error.userInfo[CKErrorUserDidResetEncryptedDataKey] != nil ? .encryptedDataReset : .zoneNotFound
        case .userDeletedZone: .userDeletedZone
        case .unknownItem: .unknownItem
        case .limitExceeded: .tooLarge
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy,
            .notAuthenticated, .accountTemporarilyUnavailable, .operationCancelled:
            .transient
        default: .other(error.code.rawValue)
        }
    }

    static func failure(_ error: any Error) -> SyncFailure {
        (error as? CKError).map(failure) ?? .transient
    }
}

/// `CKSyncEngine` behind `SyncEngineDriving`. Syncs on its own (push and a schedule) as well as
/// when asked. Holds the app's delegate weakly, as `CKSyncEngine` holds this one.
public final class CloudKitSyncEngine: SyncEngineDriving, CKSyncEngineDelegate {
    private let container: CKContainer
    private let engine = Mutex<CKSyncEngine?>(nil)
    private let delegate: Mutex<WeakDelegate>

    private struct WeakDelegate {
        weak var value: (any SyncEngineDelegate)?
    }

    /// - Parameters:
    ///   - containerIdentifier: `iCloud.com.jsayram.niftyoutfitnook`.
    ///   - state: the engine's state as it last handed it over, or `nil` for a fresh start.
    public init(containerIdentifier: String, state: Data?, delegate: any SyncEngineDelegate) {
        container = CKContainer(identifier: containerIdentifier)
        self.delegate = Mutex(WeakDelegate(value: delegate))
        let serialization = state.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: serialization, delegate: self)
        configuration.automaticallySync = true
        let made = CKSyncEngine(configuration)
        engine.withLock { $0 = made }
    }

    /// The `SyncEngineMaker` for the app.
    public static func maker(containerIdentifier: String) -> SyncEngineMaker {
        { state, delegate in
            CloudKitSyncEngine(containerIdentifier: containerIdentifier, state: state, delegate: delegate)
        }
    }

    private var syncEngine: CKSyncEngine? { engine.withLock { $0 } }

    // MARK: SyncEngineDriving

    public func add(_ changes: [SyncPendingChange]) async {
        syncEngine?.state.add(pendingRecordZoneChanges: changes.map(Self.pending))
    }

    public func remove(_ changes: [SyncPendingChange]) async {
        syncEngine?.state.remove(pendingRecordZoneChanges: changes.map(Self.pending))
    }

    public func add(_ changes: [SyncZoneChange]) async {
        syncEngine?.state.add(
            pendingDatabaseChanges: changes.map { change in
                switch change {
                case .save(let zone): .saveZone(CKRecordZone(zoneID: CloudKitRecordMapping.zoneID(zone)))
                case .delete(let zone): .deleteZone(CloudKitRecordMapping.zoneID(zone))
                }
            })
    }

    public func pendingChanges() async -> [SyncPendingChange] {
        (syncEngine?.state.pendingRecordZoneChanges ?? []).compactMap { change in
            switch change {
            case .saveRecord(let id): CloudKitRecordMapping.syncID(id).map(SyncPendingChange.save)
            case .deleteRecord(let id): CloudKitRecordMapping.syncID(id).map(SyncPendingChange.delete)
            @unknown default: nil
            }
        }
    }

    public func fetchChanges() async throws {
        do {
            try await syncEngine?.fetchChanges()
        } catch {
            throw CloudKitRecordMapping.failure(error)
        }
    }

    public func sendChanges() async throws {
        do {
            try await syncEngine?.sendChanges()
        } catch {
            throw CloudKitRecordMapping.failure(error)
        }
    }

    public func currentUser() async throws -> String? {
        do {
            guard try await container.accountStatus() == .available else { return nil }
            return try await container.userRecordID().recordName
        } catch {
            throw CloudKitRecordMapping.failure(error)
        }
    }

    public func stop() async {
        await syncEngine?.cancelOperations()
    }

    private static func pending(_ change: SyncPendingChange) -> CKSyncEngine.PendingRecordZoneChange {
        switch change {
        case .save(let id): .saveRecord(CloudKitRecordMapping.recordID(id))
        case .delete(let id): .deleteRecord(CloudKitRecordMapping.recordID(id))
        }
    }

    // MARK: CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard let delegate = delegate.withLock({ $0.value }), let translated = Self.translate(event) else { return }
        await delegate.handle(translated)
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async
        -> CKSyncEngine.RecordZoneChangeBatch?
    {
        guard let delegate = delegate.withLock({ $0.value }), await delegate.mayUpload() else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            guard let syncID = CloudKitRecordMapping.syncID(id), let record = await delegate.record(for: syncID) else {
                return nil
            }
            return CloudKitRecordMapping.ckRecord(record)
        }
    }

    static func translate(_ event: CKSyncEngine.Event) -> SyncEvent? {
        switch event {
        case .stateUpdate(let update):
            return (try? JSONEncoder().encode(update.stateSerialization)).map(SyncEvent.stateUpdate)
        case .accountChange(let change):
            switch change.changeType {
            case .signIn(let user): return .accountChange(.signIn(user: user.recordName))
            case .signOut: return .accountChange(.signOut)
            case .switchAccounts(_, let user): return .accountChange(.switchAccounts(user: user.recordName))
            @unknown default: return nil
            }
        case .fetchedDatabaseChanges(let changes):
            var zones: [SyncZone: SyncZoneDeletionReason] = [:]
            for deletion in changes.deletions {
                guard let zone = CloudKitRecordMapping.zone(deletion.zoneID) else { continue }
                switch deletion.reason {
                case .deleted: zones[zone] = .deleted
                case .purged: zones[zone] = .purged
                case .encryptedDataReset: zones[zone] = .encryptedDataReset
                @unknown default: zones[zone] = .deleted
                }
            }
            return zones.isEmpty ? nil : .zonesDeleted(zones)
        case .fetchedRecordZoneChanges(let changes):
            return .fetchedRecords(
                modified: changes.modifications.compactMap { CloudKitRecordMapping.syncRecord($0.record) },
                deleted: changes.deletions.compactMap { CloudKitRecordMapping.syncID($0.recordID) })
        case .sentDatabaseChanges(let sent):
            var failed: [SyncZone: SyncFailure] = [:]
            for save in sent.failedZoneSaves {
                if let zone = CloudKitRecordMapping.zone(save.zone.zoneID) {
                    failed[zone] = CloudKitRecordMapping.failure(save.error)
                }
            }
            for (id, error) in sent.failedZoneDeletes {
                if let zone = CloudKitRecordMapping.zone(id) { failed[zone] = CloudKitRecordMapping.failure(error) }
            }
            return .sentZones(
                saved: sent.savedZones.compactMap { CloudKitRecordMapping.zone($0.zoneID) },
                deleted: sent.deletedZoneIDs.compactMap(CloudKitRecordMapping.zone), failed: failed)
        case .sentRecordZoneChanges(let sent):
            var failedDeletes: [SyncRecordID: SyncFailure] = [:]
            for (id, error) in sent.failedRecordDeletes {
                if let syncID = CloudKitRecordMapping.syncID(id) {
                    failedDeletes[syncID] = CloudKitRecordMapping.failure(error)
                }
            }
            return .sentRecords(
                saved: sent.savedRecords.compactMap(CloudKitRecordMapping.syncRecord),
                failed: sent.failedRecordSaves.compactMap { save in
                    CloudKitRecordMapping.syncRecord(save.record).map {
                        SyncFailedSave(record: $0, failure: CloudKitRecordMapping.failure(save.error))
                    }
                },
                deleted: sent.deletedRecordIDs.compactMap(CloudKitRecordMapping.syncID), failedDeletes: failedDeletes)
        case .didFetchChanges:
            return .didFetchChanges
        default:
            return nil
        }
    }
}
