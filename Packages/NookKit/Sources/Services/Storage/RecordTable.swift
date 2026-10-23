import Foundation
import Models
import SwiftData
import Synchronization

/// Reading and writing one kind of record, for the store actors. Each actor owns its
/// `ModelContext`; this only says how a kind's rows are read and written in it.
///
/// Every write saves the context before returning, so a change that returned has reached the
/// store file. A failed save rolls the context back and throws, and nothing the actor keeps in
/// memory changes.
struct RecordTable<Value: Codable & Sendable> {
    let kind: RecordKind
    var now: @Sendable () -> Date = { .now }

    /// Every record of this kind, by key.
    func all(in context: ModelContext) throws(StoreError) -> [String: Value] {
        let kind = kind.rawValue
        let records = try storeCall {
            try context.fetch(FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.kind == kind }))
        }
        var values: [String: Value] = [:]
        for record in records {
            values[record.key] = try storeCall {
                try RecordPayload.decode(Value.self, from: record.payload, version: record.payloadVersion)
            }
        }
        return values
    }

    /// The record with this key, or `nil`.
    func value(_ key: String, in context: ModelContext) throws(StoreError) -> Value? {
        guard let record = try fetch(key, in: context) else { return nil }
        return try storeCall {
            try RecordPayload.decode(Value.self, from: record.payload, version: record.payloadVersion)
        }
    }

    /// Writes these values and removes these keys, in one save. `alongside` makes more changes
    /// in the same save (a purge's deletion markers, Phase 21b).
    func write(
        _ values: [String: Value], removing removed: [String] = [], in context: ModelContext,
        alongside: ((ModelContext) throws -> Void)? = nil
    ) throws(StoreError) {
        try saveChanges(in: context) {
            try stage(values, removing: removed, in: context)
            try alongside?(context)
        }
    }

    /// Writes these values and removes these keys in the context, without saving it.
    func stage(_ values: [String: Value], removing removed: [String] = [], in context: ModelContext) throws {
        let date = now()
        for (key, value) in values {
            let payload = try RecordPayload.encode(value)
            if let record = try fetch(key, in: context) {
                record.payload = payload
                record.payloadVersion = RecordPayload.currentVersion
                record.savedAt = date
            } else {
                context.insert(
                    StoredRecord(
                        kind: kind.rawValue, key: key, payloadVersion: RecordPayload.currentVersion,
                        payload: payload, savedAt: date))
            }
        }
        for key in removed {
            if let record = try fetch(key, in: context) { context.delete(record) }
        }
    }

    /// Removes every record of this kind.
    func removeAll(in context: ModelContext) throws(StoreError) {
        let kind = kind.rawValue
        try saveChanges(in: context) {
            try context.delete(model: StoredRecord.self, where: #Predicate { $0.kind == kind })
        }
    }

    private func fetch(_ key: String, in context: ModelContext) throws(StoreError) -> StoredRecord? {
        let kind = kind.rawValue
        var descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.kind == kind && $0.key == key })
        descriptor.fetchLimit = 1
        return try storeCall { try context.fetch(descriptor).first }
    }

}

/// Makes the changes in the context and saves them, or rolls them all back. A save is one SQLite
/// transaction, so either every change reaches the store file or none does.
func saveChanges(in context: ModelContext, _ changes: () throws -> Void) throws(StoreError) {
    do {
        try changes()
        try context.save()
    } catch {
        context.rollback()
        throw (error as? StoreError) ?? .unavailable
    }
    StoreSaveSignal.post()
}

/// Tells whoever listens that a store save went through (iCloud sync, Phase 21b, which then
/// looks for changes to upload). Nobody listens unless sync is built into the app.
public enum StoreSaveSignal {
    private static let listeners = Mutex<[UUID: @Sendable () -> Void]>([:])

    /// Starts listening. The listener runs on the saving thread, so it should only schedule work.
    public static func listen(_ listener: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        listeners.withLock { $0[id] = listener }
        return id
    }

    public static func stopListening(_ id: UUID) {
        _ = listeners.withLock { $0.removeValue(forKey: id) }
    }

    static func post() {
        for listener in listeners.withLock({ Array($0.values) }) { listener() }
    }
}

/// Runs a SwiftData call, turning anything it throws into `unavailable`. What went wrong is never
/// logged: a SwiftData error can quote the values it was saving.
func storeCall<T>(_ body: () throws -> T) throws(StoreError) -> T {
    do {
        return try body()
    } catch let error as StoreError {
        throw error
    } catch {
        throw .unavailable
    }
}
