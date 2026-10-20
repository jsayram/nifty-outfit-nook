import CryptoKit
import Foundation
import Models

// The export file (Phase 21b, docs/decisions/0004-backup-and-recovery.md, section 3).
//
// An Apple Encrypted Archive, profile `hkdf_sha256_aesctr_hmac__scrypt__none`, with a passphrase
// she chooses. Its clear prologue (`authData`) holds only `NOOK-BACKUP <format version>`. Inside,
// an Apple Archive stream of regular files, `manifest.json` first:
//
//   manifest.json            what's inside: versions, counts, and the size and SHA-256 of every
//                            other file
//   records/<kind>.json      a `records` copy: every record of one kind as readable JSON, in the
//                            app's value types
//   store/Nook.store         a `storeCopy`: the raw store, for the recovery screen
//   photos/<image id>        the photo files the records point to
//
// A Mac opens it with `aea decrypt -i <file> -o copy.aar -password <file holding the passphrase>`
// then `aa extract -i copy.aar -d <folder>` (checked on macOS 27.0.1, 20 October 2026).

/// The format's fixed values and limits.
enum BackupFormat {
    /// The outer format and manifest. A copy with a higher one is from a newer app.
    static let formatVersion = 1
    /// The clear prologue's marker. Nothing about her is ever in the clear.
    static let marker = "NOOK-BACKUP"
    static let fileExtension = "nookbackup"
    /// The type the Files sheet and the restore picker use (declared in `Configs/AppInfo.plist`).
    static let typeIdentifier = "com.jsayram.niftyoutfitnook.backup"
    static let manifestPath = "manifest.json"
    static let storePath = "store/Nook.store"

    /// The prologue for this version: `NOOK-BACKUP 1`.
    static var authData: Data { Data("\(marker) \(formatVersion)".utf8) }

    /// The format version a prologue says, or `nil` when it isn't one of ours.
    static func formatVersion(inAuthData data: Data?) -> Int? {
        guard let data, let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: " ")
        guard parts.count == 2, parts[0] == marker, let version = Int(parts[1]), version > 0 else { return nil }
        return version
    }

    /// The file name for a copy made on `date`: the date only, no name and no counts.
    static func fileName(on date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "Nifty Outfit Nook \(day).\(fileExtension)"
    }

    static func recordsPath(_ kind: RecordKind) -> String { "records/\(kind.rawValue).json" }
    static func photoPath(_ id: String) -> String { "photos/\(id)" }

    /// A path inside an archive that's safe to write under the staging folder: relative, no `..`,
    /// no empty or hidden parts, and only plain characters. Anything else stops the restore
    /// (THREAT_MODEL F4).
    static func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 255, !path.hasPrefix("/") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            !part.isEmpty && !part.hasPrefix(".") && part.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Limits on what a restore extracts, so a crafted file can't fill the phone or write outside
/// staging.
struct BackupLimits: Sendable {
    /// At most this many entries in the archive.
    var maximumEntries = 200_000
    /// The manifest is read into memory, so it's small.
    var maximumManifestBytes: Int64 = 16_000_000
    /// Space left free on the phone after staging.
    var freeSpaceMargin: Int64 = 100_000_000
}

/// `manifest.json`: what a copy holds. No content beyond counts.
struct BackupManifest: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The normal export: JSON records and photos.
        case records
        /// The raw store and photos, from the recovery screen when the app can't read the records.
        case storeCopy
    }

    struct File: Codable, Equatable, Sendable {
        var size: Int64
        var sha256: String
    }

    var formatVersion: Int
    var kind: Kind
    /// The records' JSON shape (`RecordPayload.currentVersion` when written).
    var payloadVersion: Int
    /// The store's schema version (`MigrationCoordinator.currentVersion` when written).
    var storeVersion: Int
    var appVersion: String
    var appBuild: String
    var createdAt: Date
    var counts: BackupCounts
    var includesBodyData: Bool
    var includesTryOnPhoto: Bool
    /// Every file in the archive but this one, by path.
    var files: [String: File]

    var photoCount: Int { files.keys.filter { $0.hasPrefix("photos/") }.count }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// The app's version and build, for the manifest.
enum AppVersion {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
}
