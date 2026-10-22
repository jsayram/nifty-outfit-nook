import Foundation
import Models
import SwiftData

// How the store's records become the export's readable JSON files and back (Phase 21b).
//
// Each kind of record is one file, `records/<kind>.json`: `{"kind": ..., "records": [{"key": ...,
// "value": ...}]}`, where `value` is the app's own value type (`Garment`, `Look`...) as JSON. Going
// in, every value is decoded as that type and checked as a save checks it (`StoreValidation`), and
// its key must be the one the store would give it, so a crafted file can't put anything in the
// store the app couldn't have saved itself.

/// One row of the store, as stored.
struct StoreRow: Hashable, Sendable {
    var kind: String
    var key: String
    var payloadVersion: Int
    var payload: Data

    var id: String { "\(kind)/\(key)" }

    /// Every row in the store, in one fetch, so they're consistent with each other.
    static func all(in context: ModelContext) throws -> [StoreRow] {
        try context.fetch(FetchDescriptor<StoredRecord>()).map {
            StoreRow(kind: $0.kind, key: $0.key, payloadVersion: $0.payloadVersion, payload: $0.payload)
        }
    }
}

/// One kind's conversions.
struct RecordCodec: Sendable {
    let kind: RecordKind
    /// Rows of this kind to the readable file.
    let file: @Sendable ([StoreRow]) throws -> Data
    /// The file back to rows, each value checked, written at the current payload version.
    let rows: @Sendable (_ file: Data, _ payloadVersion: Int) throws -> [StoreRow]
    /// Whether two payloads of this kind hold the same value.
    let same: @Sendable (StoreRow, StoreRow) -> Bool

    /// Every kind an export carries: everything but the content-free `UserDefaults` move marker
    /// and the AI jobs in progress (27c).
    static let all: [RecordCodec] = [
        make(.garment, Garment.self, key: { $0.id.rawValue }, check: StoreValidation.garment),
        make(.look, Look.self, key: { $0.id.rawValue }, check: StoreValidation.look),
        make(.suitcase, Suitcase.self, key: { $0.id.rawValue }),
        make(.picture, TryOnPicture.self, key: { $0.id.rawValue }),
        make(.garmentDraft, GarmentDraft.self, key: { StoredDraftStore.key($0.target) }),
        make(.lookDraft, LookDraft.self, key: { _ in RecordKind.singleKey }),
        make(.feedbackDraft, FeedbackDraft.self, key: { _ in RecordKind.singleKey }),
        make(.profile, Profile.self, key: { _ in RecordKind.singleKey }, check: StoreValidation.profile),
        make(.onboarding, StoredOnboarding.self, key: { _ in RecordKind.singleKey }),
        make(.tours, StoredTours.self, key: { _ in RecordKind.singleKey }),
        make(.deletion, StoredDeletion.self, key: nil),
        make(.restoreConflict, StoredConflict.self, key: { "\($0.kind)/\($0.key)" }),
        // 27c. Not `aiJob`: a job is this iPhone's work in progress, tied to its sign-in.
        make(.stylistThread, StylistThread.self, key: { $0.id.rawValue }),
    ]

    static let byKind: [String: RecordCodec] = Dictionary(uniqueKeysWithValues: all.map { ($0.kind.rawValue, $0) })

    /// The kinds a restore writes and Replace clears.
    static var restoredKinds: Set<String> { Set(byKind.keys) }

    private static func make<Value: Codable & Equatable & Sendable>(
        _ kind: RecordKind, _ type: Value.Type, key: (@Sendable (Value) -> String)?,
        check: @escaping @Sendable (Value) throws(StoreError) -> Value = { $0 }
    ) -> RecordCodec {
        RecordCodec(
            kind: kind,
            file: { rows in
                let entries = try rows.sorted { $0.key < $1.key }.map { row in
                    Entry(
                        key: row.key,
                        value: try RecordPayload.decode(Value.self, from: row.payload, version: row.payloadVersion))
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return try encoder.encode(File(kind: kind.rawValue, records: entries))
            },
            rows: { data, version in
                guard (1...RecordPayload.currentVersion).contains(version) else { throw BackupError.newerVersion }
                // Versions 1 and 2 share one file shape: version 2 only adds fields to garments
                // and garment drafts, which read as none when they're missing (`RecordPayload`).
                // A later shape that old files can't decode into upgrades them here first.
                let file = try JSONDecoder().decode(File<Value>.self, from: data)
                guard file.kind == kind.rawValue else { throw BackupError.damaged }
                var keys: Set<String> = []
                return try file.records.map { entry in
                    let value = try check(entry.value)
                    guard PhotoFiles.isRecordKey(entry.key), keys.insert(entry.key).inserted,
                        key.map({ $0(value) == entry.key }) ?? true
                    else { throw BackupError.damaged }
                    return StoreRow(
                        kind: kind.rawValue, key: entry.key, payloadVersion: RecordPayload.currentVersion,
                        payload: try RecordPayload.encode(value))
                }
            },
            same: { lhs, rhs in
                let left = try? RecordPayload.decode(Value.self, from: lhs.payload, version: lhs.payloadVersion)
                let right = try? RecordPayload.decode(Value.self, from: rhs.payload, version: rhs.payloadVersion)
                return left != nil && left == right
            })
    }

    private struct Entry<Value: Codable>: Codable {
        var key: String
        var value: Value
    }

    private struct File<Value: Codable>: Codable {
        var kind: String
        var records: [Entry<Value>]
    }
}

extension PhotoFiles {
    /// A record key from a file: some text with no line breaks or control characters.
    static func isRecordKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 512 && !key.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

/// What a set of rows holds, read through the value types: the counts, the sensitive parts, and
/// what the records point to.
struct BackupContents: Sendable {
    var counts = BackupCounts()
    var includesBodyData = false
    var includesTryOnPhoto = false
    /// The stored photos the records point to.
    var photoIDs: Set<String> = []
    var garmentIDs: Set<String> = []
    /// Pieces deleted for good, from the deletion markers.
    var deletedForGood: Set<String> = []
    /// Pieces and looks pointed to by looks, suitcases and pictures.
    private var referencedGarments: [String] = []
    private var referencedLooks: [String] = []
    private var lookIDs: Set<String> = []

    init(_ rows: [StoreRow]) {
        for row in rows {
            switch RecordKind(rawValue: row.kind) {
            case .garment: if let garment = decode(Garment.self, row) { add(garment) }
            case .look:
                if let look = decode(Look.self, row) {
                    counts.looks += 1
                    lookIDs.insert(look.id.rawValue)
                    referencedGarments += look.garmentIDs.map(\.rawValue)
                }
            case .suitcase:
                if let suitcase = decode(Suitcase.self, row) {
                    counts.suitcases += 1
                    referencedGarments += suitcase.garmentIDs.map(\.rawValue)
                }
            case .picture:
                if let picture = decode(TryOnPicture.self, row) {
                    counts.pictures += 1
                    referencedLooks.append(picture.lookID.rawValue)
                    if case .generated(let photo) = picture.image { addPhoto(photo) }
                }
            case .garmentDraft:
                counts.drafts += 1
                if let draft = decode(GarmentDraft.self, row) {
                    addPhoto(draft.details.photo)
                    addPhoto(draft.base.photo)
                }
            case .lookDraft, .feedbackDraft: counts.drafts += 1
            case .profile: if let profile = decode(Profile.self, row) { add(profile) }
            case .deletion: deletedForGood.insert(row.key)
            case .restoreConflict:
                // A copy's version kept for review points to its photos too (Phase 22b), so they
                // stay and travel with an export.
                if let conflict = decode(StoredConflict.self, row) { addPhotos(of: conflict) }
            default: break
            }
        }
    }

    private mutating func addPhotos(of conflict: StoredConflict) {
        let row = StoreRow(
            kind: conflict.kind, key: conflict.key, payloadVersion: conflict.payloadVersion, payload: conflict.payload)
        switch RecordKind(rawValue: conflict.kind) {
        case .garment:
            for photo in decode(Garment.self, row)?.imageReferences ?? [] { addPhoto(photo) }
        case .picture: decode(TryOnPicture.self, row)?.storedImage.map { addPhoto($0) }
        case .garmentDraft:
            if let draft = decode(GarmentDraft.self, row) {
                addPhoto(draft.details.photo)
                addPhoto(draft.base.photo)
            }
        case .profile: decode(Profile.self, row)?.tryOnPhoto.map { addPhoto($0) }
        default: break
        }
    }

    /// References to a piece, look or photo that isn't there. Kept, and shown as missing.
    func missingReferences(photosPresent: Set<String>) -> Int {
        referencedGarments.filter { !garmentIDs.contains($0) }.count
            + referencedLooks.filter { !lookIDs.contains($0) }.count
            + photoIDs.subtracting(photosPresent).count
    }

    private mutating func add(_ garment: Garment) {
        garmentIDs.insert(garment.id.rawValue)
        if garment.isDeleted { counts.recentlyDeleted += 1 } else { counts.pieces += 1 }
        addPhoto(garment.photo)
        if let cutout = garment.cutout { addPhoto(cutout.image) }
    }

    private mutating func add(_ profile: Profile) {
        includesBodyData = !profile.measurements.isEmpty || !profile.fitPieces.isEmpty
        includesTryOnPhoto = profile.tryOnPhoto.map { $0 != .noPhoto } ?? false
        if let photo = profile.tryOnPhoto { addPhoto(photo) }
    }

    private mutating func addPhoto(_ photo: PhotoReference) {
        if case .stored(let id) = photo { photoIDs.insert(id.rawValue) }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ row: StoreRow) -> Value? {
        try? RecordPayload.decode(type, from: row.payload, version: row.payloadVersion)
    }
}
