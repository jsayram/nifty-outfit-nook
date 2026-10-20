import Foundation
import Models
import SwiftData

// Phase 20a persistence spike: two offline devices and a stand-in for her private CloudKit zone.
//
// A real `CKSyncEngine` needs an iCloud account and the CloudKit entitlement, which a simulator
// test can't have. So `SpikeCloudZone` plays the server with CloudKit's rules (a change tag per
// record, a save with an old tag fails with the server's record, changes since a token), and
// `SpikeSyncDevice` plays the app's side of the engine's events: send pending changes, handle
// "server record changed", apply fetched changes, then save the new state. What still needs a real
// account is listed in docs/decisions/0003-persistence-spike.md.
//
// The engine's state lives in the same SwiftData store as the records, saved after the records it
// describes. That's THREAT_MODEL.md D8(d): the state has the store's own file protection, and a
// crash can only leave it behind the records, never ahead, so CloudKit sends the changes again.

/// One record on the server. `payload` is the garment as JSON, or `nil` once it's deleted for
/// good: the marker stays so an old device can't bring it back.
struct SpikeServerRecord: Equatable, Sendable {
    var recordName: String
    var payload: Data?
    var changeTag: Int

    var isPurged: Bool { payload == nil }
}

enum SpikeSaveResult: Sendable {
    case saved(changeTag: Int)
    /// CloudKit's `serverRecordChanged`: the save carried an old change tag.
    case serverRecordChanged(SpikeServerRecord)
}

/// A stand-in for one custom zone in her private database.
actor SpikeCloudZone {
    private var records: [String: SpikeServerRecord] = [:]
    private var changeLog: [(sequence: Int, recordName: String)] = []
    private var lastTag = 0
    private var sequence = 0

    func save(_ recordName: String, payload: Data?, expectedTag: Int?) -> SpikeSaveResult {
        if let current = records[recordName], current.isPurged || current.changeTag != expectedTag {
            return .serverRecordChanged(current)
        }
        lastTag += 1
        sequence += 1
        records[recordName] = SpikeServerRecord(recordName: recordName, payload: payload, changeTag: lastTag)
        changeLog.append((sequence, recordName))
        return .saved(changeTag: lastTag)
    }

    /// The latest version of every record changed after `token`, and the new token.
    func changes(since token: Int) -> (records: [SpikeServerRecord], token: Int) {
        let names = Set(changeLog.filter { $0.sequence > token }.map(\.recordName))
        return (names.sorted().compactMap { records[$0] }, sequence)
    }

    func garments() throws -> [Garment] {
        try records.values.compactMap(\.payload).map { try JSONDecoder().decode(Garment.self, from: $0) }
            .sorted { $0.id < $1.id }
    }

    func purgedNames() -> Set<String> {
        Set(records.values.filter(\.isPurged).map(\.recordName))
    }
}

/// What the device keeps about each synced record: the server's change tag and the version both
/// sides last agreed on, for three-way merges. In the app this goes with the record's
/// `encodeSystemFields` data.
struct SpikeSyncMetadata: Codable, Equatable, Sendable {
    var changeTag: Int
    var ancestor: Garment?
}

/// Stands in for `CKSyncEngine.State.Serialization` plus the app's own sync bookkeeping.
struct SpikeEngineState: Codable, Equatable, Sendable {
    var token = 0
    /// Records changed here and not yet acknowledged by the server.
    var pending: Set<String> = []
    var conflicts: [SpikeConflict] = []
    /// Records deleted for good on this device or by the server. Never synced again.
    var purged: Set<String> = []
}

@ModelActor
actor SpikeSyncDevice {
    static let maximumAttempts = 3

    // MARK: Local changes, made offline

    func create(_ garment: Garment) throws {
        modelContext.insert(try GarmentMapping.record(for: garment))
        var engine = try engineState()
        engine.pending.insert(garment.id.rawValue)
        try saveEngine(engine)
        try modelContext.save()
    }

    func edit(_ id: Garment.ID, _ change: @Sendable (inout Garment) -> Void) throws {
        guard let record = try garmentRecord(id.rawValue) else { throw StoreError.notFound }
        var garment = try GarmentMapping.garment(from: record)
        change(&garment)
        try GarmentMapping.apply(garment, to: record)
        var engine = try engineState()
        engine.pending.insert(id.rawValue)
        try saveEngine(engine)
        try modelContext.save()
    }

    /// Deletes a piece for good, as Recently deleted does after 30 days.
    func purge(_ id: Garment.ID) throws {
        if let record = try garmentRecord(id.rawValue) { modelContext.delete(record) }
        var engine = try engineState()
        engine.pending.insert(id.rawValue)
        engine.purged.insert(id.rawValue)
        try saveEngine(engine)
        try modelContext.save()
    }

    func garments() throws -> [Garment] {
        try modelContext.fetch(FetchDescriptor<GarmentRecord>(sortBy: [SortDescriptor(\.garmentID)]))
            .map(GarmentMapping.garment(from:))
    }

    func state() throws -> SpikeEngineState {
        try engineState()
    }

    // MARK: Sync

    /// `nextRecordZoneChangeBatch` and `sentRecordZoneChanges`: sends every pending record, and
    /// merges when the server has a newer version.
    func sendChanges(to zone: SpikeCloudZone) async throws {
        var engine = try engineState()
        for name in engine.pending.sorted() {
            for _ in 0..<Self.maximumAttempts {
                let meta = try metadata(name)
                let local = try garmentRecord(name).map(GarmentMapping.garment(from:))
                let payload = engine.purged.contains(name) ? nil : try local.map { try JSONEncoder().encode($0) }
                if payload == nil && !engine.purged.contains(name) { break }  // nothing to send
                switch await zone.save(name, payload: payload, expectedTag: meta?.changeTag) {
                case .saved(let tag):
                    try saveMetadata(SpikeSyncMetadata(changeTag: tag, ancestor: local), for: name)
                    engine.pending.remove(name)
                case .serverRecordChanged(let server):
                    try resolve(name, local: local, server: server, engine: &engine)
                }
                try saveEngine(engine)
                try modelContext.save()
                if !engine.pending.contains(name) { break }
            }
        }
    }

    /// `fetchedRecordZoneChanges`, then `stateUpdate`. The records and the state are saved one
    /// after the other, as the engine delivers them; the checkpoint between them is where a
    /// crash would leave the state behind the records.
    func fetchChanges(from zone: SpikeCloudZone) async throws {
        var engine = try engineState()
        let (changes, token) = await zone.changes(since: engine.token)
        for server in changes {
            let name = server.recordName
            let meta = try metadata(name)
            if meta?.changeTag == server.changeTag { continue }  // already applied: a repeat delivery
            let local = try garmentRecord(name).map(GarmentMapping.garment(from:))
            if server.isPurged {
                try resolve(name, local: local, server: server, engine: &engine)
                continue
            }
            let incoming = try JSONDecoder().decode(Garment.self, from: server.payload ?? Data())
            if engine.purged.contains(name) { continue }
            if engine.pending.contains(name), let local {
                let merged = SpikeMergeRules.merge(ancestor: meta?.ancestor, local: local, server: incoming)
                try write(merged.garment)
                engine.conflicts += merged.conflicts
            } else {
                try write(incoming)
            }
            try saveMetadata(SpikeSyncMetadata(changeTag: server.changeTag, ancestor: incoming), for: name)
        }
        try saveEngine(engine)
        try modelContext.save()
        try SpikeCheckpoint.hit("sync.beforeStateUpdate")
        engine.token = token
        try saveEngine(engine)
        try modelContext.save()
    }

    // MARK: Helpers

    /// The server has a newer version of a record this device changed.
    private func resolve(_ name: String, local: Garment?, server: SpikeServerRecord, engine: inout SpikeEngineState)
        throws
    {
        if server.isPurged {
            // Deleted for good elsewhere: it stays deleted. A change made here is dropped and
            // reported, never sent.
            if engine.pending.contains(name) && !engine.purged.contains(name) {
                engine.conflicts.append(
                    SpikeConflict(recordName: name, field: "deleted for good", kept: "deleted", competing: "an edit"))
            }
            if let record = try garmentRecord(name) { modelContext.delete(record) }
            engine.purged.insert(name)
            engine.pending.remove(name)
            try saveMetadata(SpikeSyncMetadata(changeTag: server.changeTag, ancestor: nil), for: name)
            return
        }
        let incoming = try JSONDecoder().decode(Garment.self, from: server.payload ?? Data())
        if engine.purged.contains(name) {
            // Deleted for good here, edited there: the deletion wins. Send it again with the
            // server's tag.
            try saveMetadata(SpikeSyncMetadata(changeTag: server.changeTag, ancestor: incoming), for: name)
            return
        }
        guard let local else {
            try write(incoming)
            engine.pending.remove(name)
            try saveMetadata(SpikeSyncMetadata(changeTag: server.changeTag, ancestor: incoming), for: name)
            return
        }
        let merged = SpikeMergeRules.merge(ancestor: try metadata(name)?.ancestor, local: local, server: incoming)
        try write(merged.garment)
        engine.conflicts += merged.conflicts
        try saveMetadata(SpikeSyncMetadata(changeTag: server.changeTag, ancestor: incoming), for: name)
        if merged.garment == incoming { engine.pending.remove(name) }
    }

    private func write(_ garment: Garment) throws {
        if let record = try garmentRecord(garment.id.rawValue) {
            try GarmentMapping.apply(garment, to: record)
        } else {
            modelContext.insert(try GarmentMapping.record(for: garment))
        }
    }

    private func garmentRecord(_ name: String) throws -> GarmentRecord? {
        var descriptor = FetchDescriptor<GarmentRecord>(predicate: #Predicate { $0.garmentID == name })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func row(_ key: String) throws -> SyncStateRecord? {
        var descriptor = FetchDescriptor<SyncStateRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func setRow(_ key: String, _ data: Data) throws {
        if let existing = try row(key) {
            existing.serialization = data
        } else {
            modelContext.insert(SyncStateRecord(key: key, serialization: data))
        }
    }

    private func engineState() throws -> SpikeEngineState {
        try row("engine").map { try JSONDecoder().decode(SpikeEngineState.self, from: $0.serialization) }
            ?? SpikeEngineState()
    }

    private func saveEngine(_ engine: SpikeEngineState) throws {
        try setRow("engine", try JSONEncoder().encode(engine))
    }

    private func metadata(_ name: String) throws -> SpikeSyncMetadata? {
        try row("meta:\(name)").map { try JSONDecoder().decode(SpikeSyncMetadata.self, from: $0.serialization) }
    }

    private func saveMetadata(_ meta: SpikeSyncMetadata, for name: String) throws {
        try setRow("meta:\(name)", try JSONEncoder().encode(meta))
    }
}
