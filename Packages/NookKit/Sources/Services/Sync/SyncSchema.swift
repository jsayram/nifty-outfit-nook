import Foundation
import Models

// Which records sync, where they go, and what they're called (decision 0004 §5).
//
// A synced record is a store row: its CloudKit record name is `<kind>.<key>` (the kind and the
// row's stable ID, such as `garment.<uuid>`), its payload is the row's JSON as stored, and its
// payload version is the row's. So the same JSON serves the store, the export and iCloud, and the
// 21c schema and every later payload version travel unchanged: a newer version than this build
// knows is held, never overwritten (`ICloudSync`). The CloudKit schema itself never changes for a
// new payload version, which matters because a production CloudKit schema can only grow.

enum SyncSchema {
    /// The kinds that sync, and their record types. Not synced: the unsent feedback note, the
    /// Stage A move marker, deletion markers (a tombstone carries them), copies kept from a
    /// restore, AI jobs in progress (this iPhone's work, tied to its sign-in), and sync's own rows.
    static let types: [RecordKind: SyncRecordType] = [
        .garment: .garment, .look: .look, .suitcase: .suitcase, .picture: .tryOnPicture,
        .garmentDraft: .draft, .lookDraft: .draft, .profile: .profile, .onboarding: .appState,
        .tours: .appState, .stylistThread: .stylistThread,
    ]

    static var syncedKinds: Set<String> { Set(types.keys.map(\.rawValue)) }

    /// `<kind>.<key>`, or `nil` for a key CloudKit can't take as a name (never the case for the
    /// app's own keys: UUIDs, `only`, `newPiece` and `garment:<uuid>`).
    static func name(kind: RecordKind, key: String) -> String? {
        let name = "\(kind.rawValue).\(key)"
        guard name.count <= 255, name.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 })
        else { return nil }
        return name
    }

    static func id(kind: RecordKind, key: String) -> SyncRecordID? {
        name(kind: kind, key: key).map { SyncRecordID(zone: .closet, name: $0) }
    }

    /// The kind and key a record name stands for, if it's a synced kind.
    static func parse(_ name: String) -> (kind: RecordKind, key: String)? {
        guard let dot = name.firstIndex(of: "."), let kind = RecordKind(rawValue: String(name[..<dot])),
            types[kind] != nil
        else { return nil }
        return (kind, String(name[name.index(after: dot)...]))
    }

    static let imagePrefix = "image."
    static func imageID(_ imageID: String, zone: SyncZone) -> SyncRecordID {
        SyncRecordID(zone: zone, name: imagePrefix + imageID)
    }

    static func imageName(of id: SyncRecordID) -> String? {
        id.name.hasPrefix(imagePrefix) ? String(id.name.dropFirst(imagePrefix.count)) : nil
    }

    static let body = SyncRecordID(zone: .me, name: "body.only")
    static let generation = SyncRecordID(zone: .control, name: "generation")

    /// CloudKit allows 1 MB per record, assets aside. Records bigger than this stay on the
    /// iPhone and are counted as too large, with room left for the system fields.
    static let maximumPayloadBytes = 900_000

    /// How many records go in one batch at most (CloudKit's limit is 400 per request).
    static let batchSize = 200
}

/// The body data in her profile, which goes in the `Me` zone, apart from the rest of the profile
/// (0004: measurements and weight, fit notes about her body, pieces that fit well, the try-on
/// photo). Her usual fit goes with it too, as the more careful reading of "fit notes".
struct SyncBodyData: Codable, Hashable, Sendable {
    var measurements: BodyMeasurements
    var usualFit: Comfort?
    var fitPieces: [FitPiece]
    var tryOnPhoto: PhotoReference?

    /// The profile without its body data, and the body data.
    static func split(_ profile: Profile) -> (profile: Profile, body: SyncBodyData) {
        var closet = profile
        closet.measurements = BodyMeasurements()
        closet.usualFit = nil
        closet.fitPieces = []
        closet.tryOnPhoto = nil
        return (
            closet,
            SyncBodyData(
                measurements: profile.measurements, usualFit: profile.usualFit, fitPieces: profile.fitPieces,
                tryOnPhoto: profile.tryOnPhoto)
        )
    }

    /// The profile from iCloud with this body data put back.
    func applied(to profile: Profile) -> Profile {
        var joined = profile
        joined.measurements = measurements
        joined.usualFit = usualFit
        joined.fitPieces = fitPieces
        joined.tryOnPhoto = tryOnPhoto
        return joined
    }
}

/// The `Control` zone's one record: a number that goes up whenever a device deletes the iCloud
/// copy on purpose, why, and when. Content-free (PRD 15.1's markers), and it stays after Delete
/// my data, so a device that was offline for months learns not to upload its old closet.
struct SyncGeneration: Codable, Hashable, Sendable {
    enum Reason: String, Codable, Sendable {
        case syncTurnedOff
        case deletedEverything
    }

    var generation: Int
    var reason: Reason
    var date: Date
}
