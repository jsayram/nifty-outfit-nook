import Foundation
import Synchronization

@testable import Services

// An in-memory stand-in for her private CloudKit database, and a stand-in for `CKSyncEngine` on
// top of it, so all of the sync logic runs in tests with no iCloud account (Phase 21b).
//
// It follows CloudKit's rules as far as the app depends on them:
// - one private database per iCloud account, custom zones in it, records in zones;
// - every save gets a new change tag; a save based on an old tag fails with the server's record
//   (`serverRecordChanged`), a save based on a tag for a record that's gone fails `unknownItem`,
//   a save into a missing zone fails `zoneNotFound`, and a full account fails `quotaExceeded`;
// - a record is at most 1 MB apart from its assets, which are kept as separate files;
// - database and zone changes are fetched since a change token, newest version only;
// - zones can go three ways: deleted by the app, purged in Settings, or lost to an encrypted data
//   reset, and the fetch says which;
// - offline, every call fails as a transient error and nothing changes.
//
// The engine stand-in does what the app relies on `CKSyncEngine` for: pending record and zone
// changes in its saved state, zone changes sent before record changes, batches asked of the
// delegate (and nothing sent when it says no), sent and fetched events, a state update after
// each, and an account change event (with its state reset) when the device's account changed.

/// A device's iCloud sign-in, which the test changes.
final class FakeICloudAccount: Sendable {
    private let user = Mutex<String?>(nil)

    init(_ user: String?) { self.user.withLock { $0 = user } }

    var current: String? { user.withLock { $0 } }
    func signIn(_ user: String?) { self.user.withLock { $0 = user } }
}

actor FakeCloudKit {
    struct Stored {
        var record: SyncRecord
        var asset: Data?
        var tag: Int
        var size: Int { (record.payload?.count ?? 0) + (asset?.count ?? 0) }
    }

    struct Zone {
        var records: [String: Stored] = [:]
        /// Every change: the sequence number and the record name.
        var log: [(sequence: Int, name: String)] = []
    }

    struct Database {
        var zones: [SyncZone: Zone] = [:]
        var zoneLog: [(sequence: Int, zone: SyncZone, deleted: SyncZoneDeletionReason?)] = []
        var quota = Int.max
        /// Every record save and deletion that reached this account's database.
        var writes = 0
    }

    static let recordLimit = 1_000_000

    private var databases: [String: Database] = [:]
    private var sequence = 0
    private var tag = 0
    private(set) var isOnline = true
    private let assets: URL

    init() {
        assets = FileManager.default.temporaryDirectory.appending(
            path: "FakeCloudKit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: assets) }

    // MARK: What the tests do and look at

    func setOnline(_ online: Bool) { isOnline = online }

    func setQuota(_ bytes: Int, for account: String) { databases[account, default: Database()].quota = bytes }

    /// Settings > iCloud > Manage > Delete data from iCloud: every zone, purged.
    func deleteInSettings(account: String) { dropAllZones(account, reason: .purged) }

    /// Her iCloud Keychain was reset: the encrypted data is gone.
    func resetEncryptedData(account: String) { dropAllZones(account, reason: .encryptedDataReset) }

    func records(_ account: String, _ zone: SyncZone) -> [SyncRecord] {
        (databases[account]?.zones[zone]?.records.values.map(\.record) ?? []).sorted { $0.id < $1.id }
    }

    func record(_ account: String, _ id: SyncRecordID) -> SyncRecord? {
        databases[account]?.zones[id.zone]?.records[id.name]?.record
    }

    func asset(_ account: String, _ id: SyncRecordID) -> Data? {
        databases[account]?.zones[id.zone]?.records[id.name]?.asset
    }

    func zones(_ account: String) -> Set<SyncZone> { Set(databases[account]?.zones.keys.map { $0 } ?? []) }

    func writes(_ account: String) -> Int { databases[account]?.writes ?? 0 }

    // MARK: What the engine calls

    func saveZones(_ account: String, saves: [SyncZone], deletes: [SyncZone]) throws -> (
        saved: [SyncZone], deleted: [SyncZone]
    ) {
        guard isOnline else { throw SyncFailure.transient }
        var database = databases[account, default: Database()]
        for zone in saves where database.zones[zone] == nil {
            database.zones[zone] = Zone()
            sequence += 1
            database.zoneLog.append((sequence, zone, nil))
        }
        for zone in deletes where database.zones[zone] != nil {
            database.zones[zone] = nil
            sequence += 1
            database.zoneLog.append((sequence, zone, .deleted))
        }
        databases[account] = database
        // Deleting a zone that isn't there leaves it as gone.
        return (saves, deletes)
    }

    func save(_ account: String, records: [SyncRecord], deletes: [SyncRecordID]) throws -> SyncEvent {
        guard isOnline else { throw SyncFailure.transient }
        var database = databases[account, default: Database()]
        var saved: [SyncRecord] = []
        var failed: [SyncFailedSave] = []
        var deleted: [SyncRecordID] = []
        var failedDeletes: [SyncRecordID: SyncFailure] = [:]
        let used = database.zones.values.flatMap(\.records.values).reduce(0) { $0 + $1.size }
        var added = 0

        for record in records {
            guard var zone = database.zones[record.id.zone] else {
                failed.append(SyncFailedSave(record: record, failure: .zoneNotFound))
                continue
            }
            if (record.payload?.count ?? 0) > Self.recordLimit {
                failed.append(SyncFailedSave(record: record, failure: .tooLarge))
                continue
            }
            let current = zone.records[record.id.name]
            let basedOn = record.systemFields.flatMap { Int(String(decoding: $0, as: UTF8.self)) }
            if let current, current.tag != basedOn {
                failed.append(SyncFailedSave(record: record, failure: .serverRecordChanged(served(current))))
                continue
            }
            if current == nil, basedOn != nil {
                failed.append(SyncFailedSave(record: record, failure: .unknownItem))
                continue
            }
            let asset = record.asset.flatMap { try? Data(contentsOf: $0) }
            let size = (record.payload?.count ?? 0) + (asset?.count ?? 0) - (current?.size ?? 0)
            if used + added + size > database.quota {
                failed.append(SyncFailedSave(record: record, failure: .quotaExceeded))
                continue
            }
            added += size
            tag += 1
            sequence += 1
            var stored = record
            stored.asset = nil
            stored.systemFields = Data(String(tag).utf8)
            stored.changeTag = "t\(tag)"
            zone.records[record.id.name] = Stored(record: stored, asset: asset, tag: tag)
            zone.log.append((sequence, record.id.name))
            database.zones[record.id.zone] = zone
            database.writes += 1
            var answer = stored
            answer.asset = record.asset
            saved.append(answer)
        }
        for id in deletes {
            guard var zone = database.zones[id.zone], zone.records[id.name] != nil else {
                failedDeletes[id] = .unknownItem
                continue
            }
            zone.records[id.name] = nil
            sequence += 1
            zone.log.append((sequence, id.name))
            database.zones[id.zone] = zone
            database.writes += 1
            deleted.append(id)
        }
        databases[account] = database
        return .sentRecords(saved: saved, failed: failed, deleted: deleted, failedDeletes: failedDeletes)
    }

    func databaseChanges(_ account: String, since token: Int) throws -> (
        deleted: [SyncZone: SyncZoneDeletionReason], zones: [SyncZone], token: Int
    ) {
        guard isOnline else { throw SyncFailure.transient }
        let database = databases[account] ?? Database()
        // A zone deleted since the token reads as deleted, even if it was made again since.
        var deleted: [SyncZone: SyncZoneDeletionReason] = [:]
        for entry in database.zoneLog where entry.sequence > token {
            if let reason = entry.deleted { deleted[entry.zone] = reason }
        }
        return (deleted, database.zones.keys.sorted(), sequence)
    }

    func zoneChanges(_ account: String, _ zone: SyncZone, since token: Int) throws -> (
        modified: [SyncRecord], deleted: [SyncRecordID], token: Int
    ) {
        guard isOnline else { throw SyncFailure.transient }
        guard let records = databases[account]?.zones[zone] else { return ([], [], sequence) }
        let names = Set(records.log.filter { $0.sequence > token }.map(\.name))
        var modified: [SyncRecord] = []
        var deleted: [SyncRecordID] = []
        for name in names.sorted() {
            if let stored = records.records[name] {
                modified.append(served(stored))
            } else {
                deleted.append(SyncRecordID(zone: zone, name: name))
            }
        }
        return (modified, deleted, sequence)
    }

    /// A record as the server hands it out: an asset as a file of its own, as CloudKit does.
    private func served(_ stored: Stored) -> SyncRecord {
        var record = stored.record
        if let asset = stored.asset {
            let url = assets.appending(path: UUID().uuidString)
            try? asset.write(to: url)
            record.asset = url
        }
        return record
    }

    private func dropAllZones(_ account: String, reason: SyncZoneDeletionReason) {
        guard var database = databases[account] else { return }
        for zone in database.zones.keys.sorted() {
            sequence += 1
            database.zoneLog.append((sequence, zone, reason))
        }
        database.zones = [:]
        databases[account] = database
    }
}

/// `CKSyncEngine`, as far as the app depends on it, on top of `FakeCloudKit`.
actor FakeSyncEngine: SyncEngineDriving {
    struct State: Codable {
        var account: String?
        var saves: [SyncRecordID] = []
        var deletes: [SyncRecordID] = []
        var zoneSaves: [SyncZone] = []
        var zoneDeletes: [SyncZone] = []
        var databaseToken = 0
        var zoneTokens: [String: Int] = [:]
    }

    private let server: FakeCloudKit
    private let account: FakeICloudAccount
    private weak var delegate: (any SyncEngineDelegate)?
    private var state: State
    /// How many batches the delegate refused (`mayUpload` said no).
    private(set) var refusedBatches = 0

    init(state: Data?, delegate: any SyncEngineDelegate, server: FakeCloudKit, account: FakeICloudAccount) {
        self.server = server
        self.account = account
        self.delegate = delegate
        self.state = state.flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    static func maker(server: FakeCloudKit, account: FakeICloudAccount) -> SyncEngineMaker {
        { state, delegate in FakeSyncEngine(state: state, delegate: delegate, server: server, account: account) }
    }

    func add(_ changes: [SyncPendingChange]) async {
        for change in changes {
            switch change {
            case .save(let id): if !state.saves.contains(id) { state.saves.append(id) }
            case .delete(let id): if !state.deletes.contains(id) { state.deletes.append(id) }
            }
        }
    }

    func remove(_ changes: [SyncPendingChange]) async {
        for change in changes {
            switch change {
            case .save(let id): state.saves.removeAll { $0 == id }
            case .delete(let id): state.deletes.removeAll { $0 == id }
            }
        }
    }

    func add(_ changes: [SyncZoneChange]) async {
        for change in changes {
            switch change {
            case .save(let zone):
                state.zoneDeletes.removeAll { $0 == zone }
                if !state.zoneSaves.contains(zone) { state.zoneSaves.append(zone) }
            case .delete(let zone):
                state.zoneSaves.removeAll { $0 == zone }
                if !state.zoneDeletes.contains(zone) { state.zoneDeletes.append(zone) }
            }
        }
    }

    func pendingChanges() async -> [SyncPendingChange] {
        state.saves.map(SyncPendingChange.save) + state.deletes.map(SyncPendingChange.delete)
    }

    func currentUser() async throws -> String? { account.current }

    func stop() async {}

    func fetchChanges() async throws {
        await checkAccount()
        guard let user = state.account, let delegate else { return }
        let database = try await server.databaseChanges(user, since: state.databaseToken)
        state.databaseToken = database.token
        if !database.deleted.isEmpty {
            for zone in database.deleted.keys { state.zoneTokens[zone.rawValue] = nil }
            await delegate.handle(.zonesDeleted(database.deleted))
        }
        for zone in database.zones {
            let changes = try await server.zoneChanges(user, zone, since: state.zoneTokens[zone.rawValue] ?? 0)
            state.zoneTokens[zone.rawValue] = changes.token
            if !changes.modified.isEmpty || !changes.deleted.isEmpty {
                await delegate.handle(.fetchedRecords(modified: changes.modified, deleted: changes.deleted))
            }
        }
        await delegate.handle(.stateUpdate(encodedState()))
        await delegate.handle(.didFetchChanges)
    }

    func sendChanges() async throws {
        await checkAccount()
        guard let user = state.account, let delegate else { return }
        guard await server.isOnline else { throw SyncFailure.transient }
        if !state.zoneSaves.isEmpty || !state.zoneDeletes.isEmpty {
            let saves = state.zoneSaves
            let deletes = state.zoneDeletes
            let result = try await server.saveZones(user, saves: saves, deletes: deletes)
            state.zoneSaves.removeAll { saves.contains($0) }
            state.zoneDeletes.removeAll { deletes.contains($0) }
            await delegate.handle(.sentZones(saved: result.saved, deleted: result.deleted, failed: [:]))
            await delegate.handle(.stateUpdate(encodedState()))
        }
        var rounds = 0
        while !(state.saves.isEmpty && state.deletes.isEmpty), rounds < 100 {
            rounds += 1
            guard await delegate.mayUpload() else {
                refusedBatches += 1
                return
            }
            let saves = Array(state.saves.prefix(SyncSchema.batchSize))
            let deletes = Array(state.deletes.prefix(SyncSchema.batchSize))
            state.saves.removeAll { saves.contains($0) }
            state.deletes.removeAll { deletes.contains($0) }
            var records: [SyncRecord] = []
            for id in saves {
                if let record = await delegate.record(for: id) { records.append(record) }
            }
            guard !records.isEmpty || !deletes.isEmpty else { continue }
            let result: SyncEvent
            do {
                result = try await server.save(user, records: records, deletes: deletes)
            } catch {
                // Still pending, as the real engine keeps them until it can send.
                state.saves = saves + state.saves
                state.deletes = deletes + state.deletes
                throw error
            }
            await delegate.handle(result)
            await delegate.handle(.stateUpdate(encodedState()))
        }
    }

    /// The device's account changed since the engine last looked: tell the app, and start over,
    /// as `CKSyncEngine` does (its pending changes are cleared).
    private func checkAccount() async {
        let current = account.current
        guard current != state.account else { return }
        let previous = state.account
        state = State()
        state.account = current
        let change: SyncAccountChange =
            switch (previous, current) {
            case (_, nil): .signOut
            case (nil, let user?): .signIn(user: user)
            case (_, let user?): .switchAccounts(user: user)
            }
        await delegate?.handle(.accountChange(change))
    }

    private func encodedState() -> Data { (try? JSONEncoder().encode(state)) ?? Data() }
}
