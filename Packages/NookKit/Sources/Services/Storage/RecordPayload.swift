import Foundation
import Models

/// How a value type becomes a record's payload and back.
///
/// Every payload is the value type's own `Codable` JSON, written at `currentVersion`. Reading
/// accepts every version up to the current one, so a value saved by an older build still opens;
/// a newer version (a store or a record from a later app) is refused rather than misread. When a
/// value type's JSON shape changes in a way old payloads can't decode into, bump `currentVersion`
/// and upgrade the old JSON here, before decoding. `RecordPayloadTests` decodes a payload saved by
/// every shipped version, so a change that breaks old payloads fails a test.
///
/// Bump it too when an older build would misread the new JSON: `JSONDecoder` ignores keys it
/// doesn't know, so an older build would drop the new fields without a word, and a save would
/// lose them. A bump makes it refuse instead. Every bump also needs a new store schema version
/// (`NookMigrationPlan`), so an older build stops at "saved by a newer version" before it reads
/// a record, and the export's manifest carries the new version, so an older build refuses the
/// copy too.
///
/// - Version 1 (Phases 21a and 21b).
/// - Version 2 (Phase 21c): garments and garment drafts gain `otherNames` and `subKind`. Version
///   1 JSON has neither, and `Garment` and `GarmentDetails` read a missing one as none, so it
///   decodes as it is. Payloads aren't rewritten: a record moves to version 2 when it's next saved.
enum RecordPayload {
    /// The payload version this build writes.
    static let currentVersion = 2

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data, version: Int) throws -> Value {
        guard (1...currentVersion).contains(version) else { throw PayloadError.unknownVersion(version) }
        return try JSONDecoder().decode(type, from: data)
    }

    enum PayloadError: Error, Equatable {
        case unknownVersion(Int)
    }
}

/// What onboarding and the tours keep (Phase 17), now as records in the store.
struct StoredOnboarding: Codable, Equatable, Sendable {
    var isCompleted: Bool
    var startingCloset: StartingCloset?
}

/// The tours seen, by ID with the version seen, and the tips switch. How and when each tour ended
/// (`TourProgress.records`) is Personal and stays in memory for the session, as in Stage A.
struct StoredTours: Codable, Equatable, Sendable {
    var seenVersions: [String: Int]
    var showsTipsOnNewScreens: Bool
}

/// That the Stage A `UserDefaults` suite was moved into the store. No content.
struct StoredDefaultsImport: Codable, Equatable, Sendable {
    var importedAt: Date
}

/// A piece deleted for good (Phase 21b). The key is the piece's ID. No content: PRD 15.2's
/// deletion markers, which an export carries and a restore obeys.
struct StoredDeletion: Codable, Equatable, Sendable {
    var deletedAt: Date
}

/// The copy's version of a record that Add what's missing found different (Phase 21b). The key
/// is `kind/key`. Kept until she reviews it (conflicts to review come with sync).
struct StoredConflict: Codable, Equatable, Sendable {
    var kind: String
    var key: String
    var payloadVersion: Int
    var payload: Data
    var foundAt: Date
}
