import CryptoKit
import Foundation
import Models
import SwiftData

// Sync's own records, kept in the store next to her data (0004 "State and bookkeeping", D8(d)).
// The value types never see them, the export leaves them out, and Delete my data erases all of
// them but a pending iCloud deletion.

/// Whether sync is on, for which account, and the engine's saved state.
struct SyncLedger: Codable, Hashable, Sendable {
    var mode: SyncMode = .off
    /// The hashed iCloud account the closet belongs to.
    var closetAccount: String?
    /// Whether sync was ever on, so there may be a copy to delete.
    var everOn = false
    /// `CKSyncEngine.State.Serialization`, as the engine handed it over.
    var engineState: Data?
    /// Decision 2: whether the `Me` zone syncs. Set from `SyncSchema.syncsBodyData` whenever sync
    /// starts or is turned on.
    var includesBodyData = SyncSchema.syncsBodyData
    var quotaFull = false
    var offline = false
    var lastConfirmedAt: Date?
    /// The highest `SyncGeneration` this device wrote or saw, and the one it last saw from others.
    var generation = 0
    var remoteGeneration: SyncGeneration?
    /// The generation this device is writing now, until iCloud confirms it.
    var outgoingGeneration: SyncGeneration?
    /// Zones the server deleted, waiting for the end of the fetch to read why.
    var deletedZones: [SyncZone: SyncZoneDeletionReason] = [:]
    /// A save found a zone missing: check for a deletion before making it again.
    var zoneMissing = false
    var notice: ICloudNotice?
    /// Zones iCloud confirmed this device deleted, during a deletion.
    var confirmedDeletes: Set<SyncZone> = []
    /// The Keychain marker of the device that saved this ledger (`SyncDeviceMarker`).
    var deviceMarker: String?
}

/// What the device keeps about one synced record.
struct SyncRecordMeta: Codable, Hashable, Sendable {
    /// The server's system fields, `nil` once the server no longer has the record.
    var systemFields: Data?
    var changeTag: String?
    /// The version both sides last agreed on. `nil` for images and tombstones.
    var ancestor: StoredPayload?
    var isTombstone = false
    /// Images: this device's records pointed to it at some point, so it's this device's to
    /// delete once nothing does. An image that arrived before its piece is never deleted early.
    var wasReferenced = false
}

/// A record from a newer app version, kept exactly as it came.
struct SyncHeldRecord: Codable, Hashable, Sendable {
    var payload: Data?
    var payloadVersion: Int
    var isTombstone: Bool
}

/// A value that lost a merge, kept for her to review. A deletion that won over an edit keeps no
/// content (the edit is "dropped and reported", 0004), since the piece was deleted for good.
struct StoredSyncConflict: Codable, Hashable, Sendable {
    enum Reason: String, Codable, Sendable {
        /// Both sides changed the same thing; this is the value that lost.
        case bothChanged
        /// Deleted for good on another device while edited here: the edit was dropped.
        case deletedElsewhere
        /// Deleted here while edited on another device: the other device's version.
        case editedElsewhere
    }

    var kind: String
    var key: String
    var fields: [String]
    var reason: Reason
    var losing: StoredPayload?
    var foundAt: Date
}

/// Delete my data's request to delete the iCloud copy. Content-free.
struct SyncPendingDeletion: Codable, Hashable, Sendable {
    var zones: [SyncZone]
    var reason: SyncGeneration.Reason
    /// The hashed account that holds the copy.
    var account: String
    var requestedAt: Date
}

enum SyncAccount {
    /// The iCloud user record name, hashed, so the store never holds it as it is.
    static func hash(_ user: String) -> String {
        SHA256.hash(data: Data("nook-icloud:\(user)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Reading and writing sync's records in one context.
struct SyncBook {
    let context: ModelContext

    private var ledgerTable: RecordTable<SyncLedger> { RecordTable(kind: .syncState) }
    private var metaTable: RecordTable<SyncRecordMeta> { RecordTable(kind: .syncRecord) }
    private var heldTable: RecordTable<SyncHeldRecord> { RecordTable(kind: .syncHeld) }
    private var conflictTable: RecordTable<StoredSyncConflict> { RecordTable(kind: .syncConflict) }
    private var deletionTable: RecordTable<SyncPendingDeletion> { RecordTable(kind: .syncPendingDeletion) }

    func ledger() -> SyncLedger { (try? ledgerTable.value(RecordKind.singleKey, in: context)) ?? SyncLedger() }
    func metas() -> [String: SyncRecordMeta] { (try? metaTable.all(in: context)) ?? [:] }
    func held() -> [String: SyncHeldRecord] { (try? heldTable.all(in: context)) ?? [:] }
    func conflicts() -> [String: StoredSyncConflict] { (try? conflictTable.all(in: context)) ?? [:] }
    func pendingDeletion() -> SyncPendingDeletion? { try? deletionTable.value(RecordKind.singleKey, in: context) }

    /// Stages changes; `save()` writes them in one transaction.
    func stage(ledger: SyncLedger) throws { try ledgerTable.stage([RecordKind.singleKey: ledger], in: context) }
    func stage(metas: [String: SyncRecordMeta] = [:], removing: [String] = []) throws {
        try metaTable.stage(metas, removing: removing, in: context)
    }
    func stage(held: [String: SyncHeldRecord] = [:], removing: [String] = []) throws {
        try heldTable.stage(held, removing: removing, in: context)
    }
    func stage(conflicts: [String: StoredSyncConflict]) throws { try conflictTable.stage(conflicts, in: context) }
    func stage(pendingDeletion: SyncPendingDeletion?) throws {
        if let pendingDeletion {
            try deletionTable.stage([RecordKind.singleKey: pendingDeletion], in: context)
        } else {
            try deletionTable.stage([:], removing: [RecordKind.singleKey], in: context)
        }
    }

    /// Forgets everything the server had: system fields, change tags and ancestors. Records the
    /// device still has are then uploaded as new, and merged by ID with any copy already there.
    func forgetServer() throws {
        try storeCall { try context.delete(model: StoredRecord.self, where: Self.kind(.syncRecord)) }
        try storeCall { try context.delete(model: StoredRecord.self, where: Self.kind(.syncHeld)) }
    }

    /// Everything sync keeps but a pending deletion: for Delete my data.
    func eraseAll() throws {
        for kind in [RecordKind.syncState, .syncRecord, .syncHeld, .syncConflict] {
            try storeCall { try context.delete(model: StoredRecord.self, where: Self.kind(kind)) }
        }
    }

    func save() throws(StoreError) {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw StoreError.unavailable
        }
    }

    private static func kind(_ kind: RecordKind) -> Predicate<StoredRecord> {
        let raw = kind.rawValue
        return #Predicate { $0.kind == raw }
    }
}

/// Delete my data's part for sync: everything sync keeps on this device but a pending iCloud
/// deletion, which has to outlive the erase (0004 §6).
struct SyncStateEraser: ErasableStore {
    let container: ModelContainer

    func eraseAll() async throws(StoreError) {
        let book = SyncBook(context: ModelContext(container))
        try storeCall { try book.eraseAll() }
        try book.save()
    }
}
