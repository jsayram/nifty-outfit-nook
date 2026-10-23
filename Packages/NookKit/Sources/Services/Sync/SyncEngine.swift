import Foundation

// The sync engine behind a protocol (Phase 21b, decision 0004 §5).
//
// `ICloudSync` talks to `SyncEngineDriving` and hears back through `SyncEngineDelegate`, in
// CloudKit's own terms (zones, records with system fields, change tags, the engine's events) but
// without CloudKit types. `CloudKitSyncEngine` is the real one, a thin wrapper over `CKSyncEngine`;
// the tests use an in-memory stand-in for CloudKit that follows the same rules, so all of the
// sync logic is tested without an iCloud account. `CKSyncEngine` itself only runs once Jose has
// made the container (docs/icloud.md).

/// Her private database's custom zones.
public enum SyncZone: String, CaseIterable, Codable, Hashable, Sendable, Comparable {
    /// Pieces, looks, suitcases, try-on pictures, the profile without body data, drafts, app
    /// state, Ask stylist conversations and their images.
    case closet = "Closet"
    /// Body data: measurements, weight, fit notes, pieces that fit well, the try-on photo. Only
    /// written when decision 2 allows (`ICloudSyncStatus.includesBodyData`).
    case me = "Me"
    /// One content-free `SyncGeneration` record, so other devices know why a zone was deleted.
    case control = "Control"

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A record's identity: its zone and its name. The name is never anything she typed.
public struct SyncRecordID: Hashable, Codable, Sendable, Comparable {
    public var zone: SyncZone
    public var name: String

    public init(zone: SyncZone, name: String) {
        self.zone = zone
        self.name = name
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.zone.rawValue, lhs.name) < (rhs.zone.rawValue, rhs.name)
    }
}

/// CloudKit record types. Generic names that carry no content: they're the only words CloudKit
/// keeps in the clear apart from record names (random IDs) and system dates.
public enum SyncRecordType: String, CaseIterable, Codable, Hashable, Sendable {
    case garment = "Garment"
    case look = "Look"
    case suitcase = "Suitcase"
    case tryOnPicture = "TryOnPicture"
    case profile = "Profile"
    case draft = "Draft"
    /// Onboarding and the tours seen.
    case appState = "AppState"
    case stylistThread = "StylistThread"
    case image = "Image"
    case body = "Body"
    case syncGeneration = "SyncGeneration"
}

/// One CloudKit record, as the app sees it. Everything about her is in `payload`, which
/// `CloudKitRecordMapping` puts in `encryptedValues`, with `payloadVersion` and `isTombstone`.
public struct SyncRecord: Hashable, Sendable {
    public var id: SyncRecordID
    public var type: SyncRecordType
    /// The value type's JSON. `nil` for an image and for a tombstone.
    public var payload: Data?
    public var payloadVersion: Int
    /// Deleted for good: content-free, so an old device can't bring the record back.
    public var isTombstone: Bool
    /// An `Image` record's file. Images are written once and never edited.
    public var asset: URL?
    /// CloudKit's system fields (`encodeSystemFields`), kept with the record so the next save
    /// says which server version it's based on. `nil` for a record the server hasn't seen.
    public var systemFields: Data?
    /// The server's change tag, to recognise a change delivered twice.
    public var changeTag: String?

    public init(
        id: SyncRecordID, type: SyncRecordType, payload: Data? = nil, payloadVersion: Int = 0,
        isTombstone: Bool = false, asset: URL? = nil, systemFields: Data? = nil, changeTag: String? = nil
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.payloadVersion = payloadVersion
        self.isTombstone = isTombstone
        self.asset = asset
        self.systemFields = systemFields
        self.changeTag = changeTag
    }
}

/// A record change waiting to be sent, as `CKSyncEngine.PendingRecordZoneChange`.
public enum SyncPendingChange: Hashable, Sendable {
    case save(SyncRecordID)
    case delete(SyncRecordID)

    public var id: SyncRecordID {
        switch self {
        case .save(let id), .delete(let id): id
        }
    }
}

/// A zone change waiting to be sent, as `CKSyncEngine.PendingDatabaseChange`.
public enum SyncZoneChange: Hashable, Sendable {
    case save(SyncZone)
    case delete(SyncZone)
}

/// `CKSyncEngine.Event.AccountChange`, with the user record names.
public enum SyncAccountChange: Hashable, Sendable {
    case signIn(user: String)
    case signOut
    case switchAccounts(user: String)
}

/// Why a zone was deleted (`CKDatabase.DatabaseChange.Deletion.Reason`).
public enum SyncZoneDeletionReason: String, Hashable, Codable, Sendable {
    /// The app deleted it, on another device.
    case deleted
    /// She deleted the app's data in Settings > iCloud.
    case purged
    /// Her iCloud encryption keys were reset, and the encrypted data with them.
    case encryptedDataReset
}

/// Why a record or zone wasn't saved, from the `CKError` codes the app acts on.
public enum SyncFailure: Error, Hashable, Sendable {
    /// The save carried an old change tag. The server's record comes with it, to merge.
    case serverRecordChanged(SyncRecord?)
    /// Her iCloud storage is full.
    case quotaExceeded
    /// No network, iCloud busy or unavailable, rate limited, not signed in: the engine retries.
    case transient
    /// The zone isn't there (yet, or any more).
    case zoneNotFound
    /// `zoneNotFound` with `CKErrorUserDidResetEncryptedDataKey`.
    case encryptedDataReset
    /// She deleted the app's data in Settings while the save was on its way.
    case userDeletedZone
    /// The record isn't on the server any more.
    case unknownItem
    /// Bigger than CloudKit allows for one record.
    case tooLarge
    /// Anything else, by `CKError.Code` raw value.
    case other(Int)
}

/// What the engine tells the app, as `CKSyncEngine.Event`, in the order it happens.
public enum SyncEvent: Sendable {
    /// Save it after the records it describes (THREAT_MODEL D8(d)).
    case stateUpdate(Data)
    case accountChange(SyncAccountChange)
    /// Zones deleted on the server since the last fetch.
    case zonesDeleted([SyncZone: SyncZoneDeletionReason])
    case fetchedRecords(modified: [SyncRecord], deleted: [SyncRecordID])
    case sentZones(saved: [SyncZone], deleted: [SyncZone], failed: [SyncZone: SyncFailure])
    case sentRecords(
        saved: [SyncRecord], failed: [SyncFailedSave], deleted: [SyncRecordID],
        failedDeletes: [SyncRecordID: SyncFailure])
    /// A fetch finished: every change it found has been delivered.
    case didFetchChanges
}

/// A record save that failed, with the record that was sent.
public struct SyncFailedSave: Hashable, Sendable {
    public var record: SyncRecord
    public var failure: SyncFailure

    public init(record: SyncRecord, failure: SyncFailure) {
        self.record = record
        self.failure = failure
    }
}

/// The app's side of the engine: `ICloudSync`.
public protocol SyncEngineDelegate: AnyObject, Sendable {
    func handle(_ event: SyncEvent) async
    /// Asked before every batch. `false` sends nothing: sync is off or paused, or the iCloud
    /// account signed in now isn't the one this closet belongs to.
    func mayUpload() async -> Bool
    /// The record to save for a pending change, read fresh, or `nil` to skip it.
    func record(for id: SyncRecordID) async -> SyncRecord?
}

/// The engine: `CloudKitSyncEngine` in the app, a stand-in in the tests.
public protocol SyncEngineDriving: Sendable {
    func add(_ changes: [SyncPendingChange]) async
    func remove(_ changes: [SyncPendingChange]) async
    func add(_ changes: [SyncZoneChange]) async
    func pendingChanges() async -> [SyncPendingChange]
    /// Fetches what changed on the server. Throws `SyncFailure.transient` when offline.
    func fetchChanges() async throws
    /// Sends what's pending, asking the delegate for each batch.
    func sendChanges() async throws
    /// The iCloud user record name signed in now, or `nil` when signed out.
    func currentUser() async throws -> String?
    /// Stops any operation in flight.
    func stop() async
}

/// Makes the engine from its saved state, with the app as its delegate (held weakly).
public typealias SyncEngineMaker =
    @Sendable (_ state: Data?, _ delegate: any SyncEngineDelegate) ->
    any SyncEngineDriving
