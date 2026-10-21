import Foundation
import Testing

@testable import Services

/// Files the Phase 21b build made before the store's first real schema change (Phase 21c), kept
/// so every later build proves it still reads them. They were made on 20 October 2026 by
/// `develop` at b0c063c, with `BackupTestBed.seedDemo()`: the demo closet, three photo files,
/// measurements, drafts of each kind, the feedback note, onboarding and a tour flag.
///
/// - `Nook-v1.store`: the store itself, at schema version 1 with version 1 payloads, as one file.
/// - `records-demo-1.nookbackup`: Export a copy of it (format 1, payload 1). Passphrase below.
/// - `store-copy-1.nookbackup`: the recovery screen's Export a copy of it (a raw schema
///   version 1 store). Passphrase below.
/// - `rows-v1.json`: every row of that store, `kind/key` to `payloadVersion:base64 payload`.
///
/// Never remake or edit them to make a test pass. A later format or schema adds files of its own.
enum Phase21bFixtures {
    static let recordsPassphrase = "phase 21b demo fixture"
    static let storeCopyPassphrase = "phase 21b store copy fixture"

    static func url(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    /// The rows the 21b store held, as stored.
    static func rows() throws -> [StoreRow] {
        let data = try Data(contentsOf: try url("rows-v1", "json"))
        let entries = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        return try entries.map { id, value in
            let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
            let fields = value.split(separator: ":", maxSplits: 1).map(String.init)
            let version = try #require(Int(fields[0]))
            let payload = try #require(Data(base64Encoded: fields[1]))
            return StoreRow(kind: parts[0], key: parts[1], payloadVersion: version, payload: payload)
        }
    }
}
