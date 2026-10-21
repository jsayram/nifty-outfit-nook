import Foundation
import Models
import Security
import SwiftData

/// Export a copy, Check a copy and Restore on the store on the iPhone (Phase 21b). One actor, so
/// two exports or restores never run at once, and all of it runs off the main thread.
public actor LocalBackupService: BackupService {
    private let container: ModelContainer
    private let location: BackupLocation
    private var checked: StagedCopy?
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    /// Free space for tests. `nil` reads the volume.
    private let freeSpace: (@Sendable () -> Int64)?

    public init(container: ModelContainer, location: BackupLocation) {
        self.init(container: container, location: location, now: { .now })
    }

    init(
        container: ModelContainer, location: BackupLocation, now: @escaping @Sendable () -> Date,
        calendar: Calendar = .current, freeSpace: (@Sendable () -> Int64)? = nil
    ) {
        self.container = container
        self.location = location
        self.now = now
        self.calendar = calendar
        self.freeSpace = freeSpace
    }

    public func summary() throws(BackupError) -> BackupSummary {
        exporter.summary(of: try rows())
    }

    public nonisolated func makePassphrase() -> String {
        BackupPassphraseMaker.make()
    }

    public func export(passphrase: String) throws(BackupError) -> BackupFile {
        guard passphrase.count >= BackupPassphrase.minimumLength else { throw .passphrase(.tooShort) }
        return try exporter.export(try rows(), passphrase: passphrase)
    }

    public func discard(_ file: BackupFile) {
        BackupFiles.discard(file, in: location)
    }

    public func check(_ url: URL, passphrase: String) throws(BackupError) -> BackupPreview {
        discardChecked()
        // A file from the Files picker is outside the app's container until it's opened this way.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var checker = RestoreChecker(location: location)
        checker.reader.freeSpace = freeSpace
        let copy = try checker.check(url, passphrase: passphrase)
        checked = copy
        return RestoreChecker.preview(of: copy, phone: try rows())
    }

    public func restore(_ preview: BackupPreview, as mode: RestoreMode) throws(BackupError) -> RestoreOutcome {
        guard let copy = checked, copy.id == preview.id else { throw .nothingToRestore }
        checked = nil
        return try committer.restore(copy, as: mode)
    }

    public func discardChecked() {
        if let copy = checked { BackupLocation.remove(copy.folder) }
        checked = nil
    }

    public func undoAvailable() -> UndoRestore? {
        committer.undoAvailable()
    }

    public func undoRestore() throws(BackupError) {
        try committer.undo()
    }

    private var exporter: BackupExporter {
        BackupExporter(location: location, now: now, calendar: calendar, freeSpace: freeSpace)
    }

    private var committer: RestoreCommitter {
        RestoreCommitter(container: container, location: location, now: now, freeSpace: freeSpace)
    }

    private func rows() throws(BackupError) -> [StoreRow] {
        do {
            return try StoreRow.all(in: ModelContext(container))
        } catch {
            throw .failed
        }
    }
}

/// Export a copy from the recovery screen (0004 section 7): the raw store and photos, encrypted
/// the same way, when this build can't open the store. It needs no open container.
public struct StoreCopyExport: StoreCopyExporter {
    let location: BackupLocation

    public init(location: BackupLocation) {
        self.location = location
    }

    public func makePassphrase() -> String {
        BackupPassphraseMaker.make()
    }

    public func exportStoreCopy(passphrase: String) async throws(BackupError) -> BackupFile {
        guard passphrase.count >= BackupPassphrase.minimumLength else { throw .passphrase(.tooShort) }
        return try BackupExporter(location: location).exportStoreCopy(passphrase: passphrase)
    }

    public func discard(_ file: BackupFile) async {
        BackupFiles.discard(file, in: location)
    }
}

/// Delete my data's part for backups: her photo files, a checked copy, unsaved exports, the
/// restore's safety copy and journal, and the copies' versions kept for review. Exports she saved
/// elsewhere stay where she put them; the screen says so.
public struct BackupDataEraser: ErasableStore {
    let container: ModelContainer
    let location: BackupLocation

    public init(container: ModelContainer, location: BackupLocation) {
        self.container = container
        self.location = location
    }

    public func eraseAll() async throws(StoreError) {
        for folder in [location.photos, location.thumbnails, location.staging, location.exports, location.safetyCopy] {
            BackupLocation.remove(folder)
        }
        BackupLocation.remove(location.restoreJournal)
        try RecordTable<StoredConflict>(kind: .restoreConflict).removeAll(in: ModelContext(container))
    }
}

enum BackupFiles {
    /// Removes an export's folder, if it's one of ours.
    static func discard(_ file: BackupFile, in location: BackupLocation) {
        let folder = file.url.deletingLastPathComponent().standardizedFileURL
        guard folder.path.hasPrefix(location.exports.standardizedFileURL.path + "/") else { return }
        BackupLocation.remove(folder)
    }
}

/// A generated passphrase from `SecRandomCopyBytes` (0004 section 3).
enum BackupPassphraseMaker {
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: BackupPassphrase.generatedLength)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Never seen in practice. The system generator is also cryptographically secure on
            // Apple platforms (arc4random), so it's a safe stand-in.
            var generator = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return BackupPassphrase.generated(from: bytes)
    }
}
