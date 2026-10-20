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
enum RecordPayload {
    /// The payload version this build writes.
    static let currentVersion = 1

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
