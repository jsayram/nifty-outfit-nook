import AppleArchive
import CryptoKit
import Foundation
import Models
import System

// Writing and reading the encrypted archive (see `BackupFormat`). AEA authenticates every
// segment, so a changed, cut or reordered byte fails as it's read; the reader adds the checks AEA
// can't make: the manifest, bounded extraction, and no bytes after the end.

/// Writes an encrypted archive, one file at a time. The data is encrypted as it's written: no
/// unencrypted copy of the closet is ever put on disk.
final class BackupArchiveWriter {
    private let url: URL
    private let file: ArchiveByteStream
    private let encryption: ArchiveByteStream
    private let encoder: ArchiveStream
    private var finished = false

    init(url: URL, passphrase: String) throws(BackupError) {
        let context = ArchiveEncryptionContext(
            profile: .hkdf_sha256_aesctr_hmac__scrypt__none, compressionAlgorithm: .lzfse)
        context.authData = BackupFormat.authData
        do {
            try context.setPassword(passphrase)
        } catch {
            throw .passphrase(.tooShort)
        }
        guard
            let file = ArchiveByteStream.fileStream(
                path: FilePath(url.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: [.ownerReadWrite])
        else { throw .failed }
        guard let encryption = ArchiveByteStream.encryptionStream(writingTo: file, encryptionContext: context),
            let encoder = ArchiveStream.encodeStream(writingTo: encryption)
        else {
            try? file.close()
            try? FileManager.default.removeItem(at: url)
            throw .failed
        }
        self.url = url
        self.file = file
        self.encryption = encryption
        self.encoder = encoder
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    /// Adds a file from memory.
    func add(path: String, data: Data) throws {
        try writeHeader(path: path, size: UInt64(data.count))
        if !data.isEmpty {
            try data.withUnsafeBytes { try encoder.writeBlob(key: Self.data, from: $0) }
        }
    }

    /// Adds a file from disk in 1 MiB pieces, hashing it again on the way. If it no longer
    /// matches `sha256` (it changed after the manifest was made), the export stops.
    func add(path: String, file source: URL, size: Int64, sha256: String) throws {
        try writeHeader(path: path, size: UInt64(size))
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var hasher = SHA256()
        var written: Int64 = 0
        // Phase 32a: each piece is read inside its own autorelease pool. `FileHandle.read` hands
        // back memory Foundation only frees when the pool it runs in drains, and an export runs in
        // one pool from start to end, so every photo stayed in memory until the export was done:
        // 1,000 photos of 1.8 MB made a 1.7 GB peak (measured), which ends the app on an iPhone 12.
        var finished = false
        while !finished {
            try autoreleasepool {
                guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else {
                    finished = true
                    return
                }
                written += Int64(chunk.count)
                guard written <= size else { throw BackupError.failed }
                hasher.update(data: chunk)
                try chunk.withUnsafeBytes { try encoder.writeBlob(key: Self.data, from: $0) }
            }
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard written == size, hash == sha256 else { throw BackupError.failed }
    }

    /// Adds an entry exactly as given, for the tests' crafted archives: any type, any path.
    func addRaw(type: ArchiveHeader.EntryType, path: String, data: Data?) throws {
        let header = ArchiveHeader()
        header.append(.uint(key: Self.type, value: UInt64(type.rawValue)))
        header.append(.string(key: Self.path, value: path))
        if let data { header.append(.blob(key: Self.data, size: UInt64(data.count))) }
        try encoder.writeHeader(header)
        if let data, !data.isEmpty {
            try data.withUnsafeBytes { try encoder.writeBlob(key: Self.data, from: $0) }
        }
    }

    /// Closes the archive. Until this returns, the file isn't a valid copy.
    func finish() throws {
        finished = true
        try encoder.close()
        try encryption.close()
        try file.close()
    }

    /// Stops and deletes the partial file.
    func cancel() {
        guard !finished else { return }
        finished = true
        encoder.cancel()
        try? encryption.close()
        try? file.close()
        try? FileManager.default.removeItem(at: url)
    }

    private func writeHeader(path: String, size: UInt64) throws {
        let header = ArchiveHeader()
        header.append(.uint(key: Self.type, value: UInt64(ArchiveHeader.EntryType.regularFile.rawValue)))
        header.append(.string(key: Self.path, value: path))
        header.append(.blob(key: Self.data, size: size))
        try encoder.writeHeader(header)
    }

    static var type: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("TYP") }
    static var path: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("PAT") }
    static var data: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("DAT") }
}

/// Opens an encrypted archive and extracts it into a staging folder, checking everything on
/// the way. Returns the manifest once every file is staged and matches it. Nothing is written
/// outside `staging`.
struct BackupArchiveReader {
    var limits = BackupLimits()
    /// Free space where staging is, in bytes. `nil` reads the volume.
    var freeSpace: (@Sendable () -> Int64)?

    func extract(_ url: URL, passphrase: String, into staging: URL) throws(BackupError) -> BackupManifest {
        guard
            let file = ArchiveByteStream.fileStream(
                path: FilePath(url.path), mode: .readOnly, options: [], permissions: [])
        else { throw .notABackup }
        defer { try? file.close() }
        guard let context = ArchiveEncryptionContext(from: file),
            context.profile == .hkdf_sha256_aesctr_hmac__scrypt__none,
            let version = BackupFormat.formatVersion(inAuthData: context.authData)
        else { throw .notABackup }
        guard version <= BackupFormat.formatVersion else { throw .newerVersion }
        do {
            try context.setPassword(passphrase)
        } catch {
            throw .wrongPassphrase
        }
        guard let decryption = ArchiveByteStream.decryptionStream(readingFrom: file, encryptionContext: context)
        else { throw .wrongPassphrase }
        guard let decoder = ArchiveStream.decodeStream(readingFrom: decryption) else {
            try? decryption.close()
            throw .damaged
        }
        let manifest: BackupManifest
        do {
            manifest = try extractEntries(from: decoder, into: staging)
            try decoder.close()
            try decryption.close()
        } catch {
            decoder.cancel()
            try? decryption.close()
            throw (error as? BackupError) ?? .damaged
        }
        // AEA ignores bytes after its end, so a file longer than the container is refused here.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
        guard size == Int64(context.containerSize) else { throw .damaged }
        return manifest
    }

    private func extractEntries(from decoder: ArchiveStream, into staging: URL) throws -> BackupManifest {
        guard let first = try decoder.readHeader(), let entry = Entry(first), entry.isFile,
            entry.path == BackupFormat.manifestPath, entry.size <= limits.maximumManifestBytes
        else { throw BackupError.damaged }
        let manifestData = try readData(entry, from: decoder)
        guard let manifest = try? BackupManifest.decoder().decode(BackupManifest.self, from: manifestData)
        else { throw BackupError.damaged }
        guard manifest.formatVersion <= BackupFormat.formatVersion else { throw BackupError.newerVersion }
        guard manifest.files.count < limits.maximumEntries,
            manifest.files.keys.allSatisfy(BackupFormat.isSafePath)
        else { throw BackupError.damaged }

        let available = freeSpace?() ?? Self.volumeSpace(at: staging)
        // 32b: summed without overflow. A crafted manifest with sizes near Int64.max made `+` trap
        // and end the app; now it is damaged, like any other size the files can't have.
        var needed: Int64 = 0
        for file in manifest.files.values {
            let (sum, overflow) = needed.addingReportingOverflow(max(file.size, 0))
            guard !overflow else { throw BackupError.damaged }
            needed = sum
        }
        let (neededWithMargin, marginOverflow) = needed.addingReportingOverflow(limits.freeSpaceMargin)
        guard !marginOverflow else { throw BackupError.damaged }
        guard neededWithMargin <= available else {
            throw BackupError.notEnoughSpace(needed: neededWithMargin)
        }

        var seen: Set<String> = [BackupFormat.manifestPath]
        var entries = 1
        var staged: Int64 = 0
        while let header = try decoder.readHeader() {
            entries += 1
            guard entries <= limits.maximumEntries, let entry = Entry(header), BackupFormat.isSafePath(entry.path)
            else { throw BackupError.damaged }
            if entry.isDirectory { continue }
            guard entry.isFile, let expected = manifest.files[entry.path], !seen.contains(entry.path),
                entry.size == expected.size
            else { throw BackupError.damaged }
            seen.insert(entry.path)
            staged += entry.size
            guard staged + limits.freeSpaceMargin <= available else {
                throw BackupError.notEnoughSpace(needed: neededWithMargin)
            }
            let hash = try stage(entry, from: decoder, under: staging)
            guard hash == expected.sha256 else { throw BackupError.damaged }
        }
        guard seen.count == manifest.files.count + 1 else { throw BackupError.damaged }
        return manifest
    }

    private func readData(_ entry: Entry, from decoder: ArchiveStream) throws -> Data {
        var data = Data(count: Int(entry.size))
        if entry.size > 0 {
            try data.withUnsafeMutableBytes { try decoder.readBlob(key: BackupArchiveWriter.data, into: $0) }
        }
        return data
    }

    /// Writes one entry under staging in 1 MiB pieces, returning its SHA-256.
    private func stage(_ entry: Entry, from decoder: ArchiveStream, under staging: URL) throws -> String {
        let destination = staging.appending(path: entry.path)
        // Belt and braces: the path checks already rule this out.
        guard destination.standardizedFileURL.path.hasPrefix(staging.standardizedFileURL.path + "/") else {
            throw BackupError.damaged
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        guard
            FileManager.default.createFile(
                atPath: destination.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
        else { throw BackupError.failed }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = entry.size
        var buffer = Data(count: 1 << 20)
        while remaining > 0 {
            let count = Int(min(remaining, Int64(buffer.count)))
            try buffer.withUnsafeMutableBytes { raw in
                try decoder.readBlob(
                    key: BackupArchiveWriter.data, into: UnsafeMutableRawBufferPointer(rebasing: raw[0..<count]))
            }
            let piece = buffer.prefix(count)
            hasher.update(data: piece)
            try handle.write(contentsOf: piece)
            remaining -= Int64(count)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func volumeSpace(at url: URL) -> Int64 {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// One archive entry's header: its type, path and data size.
    private struct Entry {
        var type: UInt64
        var path: String
        var size: Int64

        init?(_ header: ArchiveHeader) {
            guard case .uint(_, let type)? = header.field(forKey: BackupArchiveWriter.type),
                case .string(_, let path)? = header.field(forKey: BackupArchiveWriter.path)
            else { return nil }
            self.type = type
            self.path = path
            if case .blob(_, let size, _)? = header.field(forKey: BackupArchiveWriter.data) {
                guard size <= UInt64(Int64.max) else { return nil }
                self.size = Int64(size)
            } else {
                size = 0
            }
        }

        var isFile: Bool { type == UInt64(ArchiveHeader.EntryType.regularFile.rawValue) }
        var isDirectory: Bool { type == UInt64(ArchiveHeader.EntryType.directory.rawValue) && size == 0 }
    }
}
