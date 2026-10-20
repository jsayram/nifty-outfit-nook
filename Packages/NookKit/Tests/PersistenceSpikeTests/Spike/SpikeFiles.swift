import CryptoKit
import Foundation

// Phase 20a persistence spike: where a store's files live, image files, and checkpoints.

/// A crash point the tests and the kill harness can stop at. The migration code calls `hit` at
/// each step; a test throws `SimulatedKill` from the handler, and the harness kills its own
/// process there with SIGKILL. A task-local handler keeps parallel tests apart.
enum SpikeCheckpoint {
    @TaskLocal static var handler: (@Sendable (String) throws -> Void)?

    static func hit(_ name: String) throws {
        try handler?(name)
    }
}

/// What a test throws to stand for the process dying at a checkpoint.
struct SimulatedKill: Error, Equatable {
    let checkpoint: String
}

/// The files of one store: the SQLite store, its image folder, the migration journal and the
/// recovery snapshot, all in one folder.
struct SpikeStoreLocation: Sendable {
    let directory: URL

    var storeURL: URL { directory.appending(path: "Closet.store") }
    var imagesDirectory: URL { Self.imagesDirectory(forStore: storeURL) }
    var journalURL: URL { directory.appending(path: "MigrationJournal.json") }
    var recoveryDirectory: URL { directory.appending(path: "Recovery") }
    var snapshotURL: URL { recoveryDirectory.appending(path: "Snapshot.store") }

    static func imagesDirectory(forStore storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appending(path: "Images")
    }

    /// A new, empty folder under the temporary directory.
    static func temporary(_ label: String = "store") throws -> SpikeStoreLocation {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PersistenceSpike")
            .appending(path: "\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SpikeStoreLocation(directory: directory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Image files named by stable ID, written whole or not at all.
struct SpikeImageFiles: Sendable {
    let directory: URL

    struct FileInfo: Hashable, Sendable {
        let sha256: String
        let byteCount: Int
    }

    static func fileName(forPhoto id: String) -> String { "\(id).jpg" }

    /// Writes the bytes to a temporary file and renames it into place, so a crash leaves either
    /// the old file, the new one, or none, never half a file. Complete file protection on a
    /// device (the simulator doesn't enforce it).
    func write(_ data: Data, named name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
            try data.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: directory.appending(path: name), options: [.atomic])
        #endif
    }

    func read(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appending(path: name))
    }

    /// The hash and size of a file, or `nil` when it isn't there.
    func describe(_ name: String) throws -> FileInfo? {
        let url = directory.appending(path: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return FileInfo(sha256: Self.sha256(data), byteCount: data.count)
    }

    func delete(_ name: String) throws {
        let url = directory.appending(path: name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Every file name in the folder.
    func names() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Photo-sized stand-in images: real JPEG files, different for every seed, about the size of a
/// downsampled phone photo. Noise compresses badly, so the files are realistic in size.
enum SpikeSampleImages {
    static func jpeg(seed: UInt64, byteCount: Int = 120_000) -> Data {
        // A JPEG header and trailer around seeded noise. Nothing decodes these; the spike only
        // needs files of a real size whose bytes differ, to hash and copy.
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        var bytes = [UInt8](repeating: 0, count: byteCount)
        bytes[0] = 0xFF
        bytes[1] = 0xD8
        for index in 2..<(byteCount - 2) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
        }
        bytes[byteCount - 2] = 0xFF
        bytes[byteCount - 1] = 0xD9
        return Data(bytes)
    }
}
