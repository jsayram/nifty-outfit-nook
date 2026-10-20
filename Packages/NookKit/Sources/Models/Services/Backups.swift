import Foundation

// Export a copy, Check a copy and Restore (Phase 21b, docs/decisions/0004-backup-and-recovery.md,
// sections 3 and 4). The screens only see `BackupService`; the store on the iPhone implements it
// (`LocalBackupService` in Services). The debug sample closet lives in memory and has none, so its
// screens don't offer backups.

/// Makes and restores encrypted copies of her closet.
public protocol BackupService: Sendable {
    /// What an export would hold now, for the preview before she exports.
    func summary() async throws(BackupError) -> BackupSummary
    /// A new random passphrase, `BackupPassphrase.generatedLength` letters and digits in groups.
    func makePassphrase() -> String
    /// Writes an encrypted copy of everything to a temporary file, for the Files sheet to save.
    /// The passphrase is used once and never kept.
    func export(passphrase: String) async throws(BackupError) -> BackupFile
    /// Deletes the temporary export once it's saved, or if she cancels.
    func discard(_ file: BackupFile) async
    /// Opens a copy and runs every check up to the preview. Nothing in the app changes; the
    /// opened copy waits in staging for `restore` until `discardChecked`.
    func check(_ url: URL, passphrase: String) async throws(BackupError) -> BackupPreview
    /// Writes the checked copy into the app, after taking a safety copy. Afterwards the app
    /// rebuilds its screens on the restored closet.
    func restore(_ preview: BackupPreview, as mode: RestoreMode) async throws(BackupError) -> RestoreOutcome
    /// Throws away a checked copy that won't be restored.
    func discardChecked() async
    /// The safety copy from the last restore, while Undo restore is still possible.
    func undoAvailable() async -> UndoRestore?
    /// Puts back the closet from before the last restore.
    func undoRestore() async throws(BackupError)
}

/// Export a copy from the recovery screen (0004 section 7), when the store couldn't be opened: the
/// raw store and photos, encrypted the same way, for a later version of the app to restore.
public protocol StoreCopyExporter: Sendable {
    func makePassphrase() -> String
    func exportStoreCopy(passphrase: String) async throws(BackupError) -> BackupFile
    func discard(_ file: BackupFile) async
}

/// What's in a closet, counted for a preview. Recently deleted pieces count separately.
public struct BackupCounts: Hashable, Sendable, Codable {
    public var pieces: Int
    public var recentlyDeleted: Int
    public var looks: Int
    public var suitcases: Int
    public var pictures: Int
    public var drafts: Int

    public init(
        pieces: Int = 0, recentlyDeleted: Int = 0, looks: Int = 0, suitcases: Int = 0, pictures: Int = 0,
        drafts: Int = 0
    ) {
        self.pieces = pieces
        self.recentlyDeleted = recentlyDeleted
        self.looks = looks
        self.suitcases = suitcases
        self.pictures = pictures
        self.drafts = drafts
    }

    /// Nothing at all: a new phone, or a closet she hasn't started.
    public var isEmpty: Bool { self == BackupCounts() }
}

/// What an export would hold, before she exports.
public struct BackupSummary: Hashable, Sendable {
    public var counts: BackupCounts
    /// Photo files that go with it.
    public var photos: Int
    /// About how big the file will be, in bytes.
    public var estimatedBytes: Int64
    /// Measurements or weight are in it: named on their own line, as the most sensitive part.
    public var includesBodyData: Bool
    public var includesTryOnPhoto: Bool

    public init(
        counts: BackupCounts, photos: Int, estimatedBytes: Int64, includesBodyData: Bool, includesTryOnPhoto: Bool
    ) {
        self.counts = counts
        self.photos = photos
        self.estimatedBytes = estimatedBytes
        self.includesBodyData = includesBodyData
        self.includesTryOnPhoto = includesTryOnPhoto
    }
}

/// A finished export, waiting in a temporary folder for the Files sheet.
public struct BackupFile: Hashable, Sendable {
    public var url: URL
    public var bytes: Int64

    public init(url: URL, bytes: Int64) {
        self.url = url
        self.bytes = bytes
    }

    /// The file name she sees: `Nifty Outfit Nook 2026-10-20.nookbackup`. The date only.
    public var name: String { url.lastPathComponent }
}

/// A copy that passed every check, waiting in staging. Nothing in the app has changed.
public struct BackupPreview: Hashable, Sendable, Identifiable {
    public var id: UUID
    /// When the copy was made.
    public var createdAt: Date
    public var inCopy: BackupCounts
    public var onPhone: BackupCounts
    public var photos: Int
    public var includesBodyData: Bool
    public var includesTryOnPhoto: Bool
    /// Pieces in the copy that were deleted for good, here or in the copy. They never come back.
    public var deletedForGood: Int
    /// References to a piece or photo the copy doesn't hold. Kept, and shown as missing.
    public var missingReferences: Int

    public init(
        id: UUID, createdAt: Date, inCopy: BackupCounts, onPhone: BackupCounts, photos: Int = 0,
        includesBodyData: Bool = false, includesTryOnPhoto: Bool = false, deletedForGood: Int = 0,
        missingReferences: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.inCopy = inCopy
        self.onPhone = onPhone
        self.photos = photos
        self.includesBodyData = includesBodyData
        self.includesTryOnPhoto = includesTryOnPhoto
        self.deletedForGood = deletedForGood
        self.missingReferences = missingReferences
    }
}

/// How a checked copy goes into the app.
public enum RestoreMode: String, Hashable, Sendable, Codable {
    /// The app's closet becomes the copy's. For a new phone, or to go back.
    case replace
    /// Only what the app doesn't have is added. Nothing is removed; a piece that differs keeps
    /// this iPhone's version, and the copy's is kept for review.
    case addMissing
}

/// What a restore did.
public struct RestoreOutcome: Hashable, Sendable {
    /// What the app holds now.
    public var counts: BackupCounts
    /// Records added from the copy (Add what's missing), or every record (Replace).
    public var added: Int
    /// Add what's missing: records that differ, kept for review.
    public var conflicts: Int
    /// Pieces deleted for good that the copy still had. Left out.
    public var deletedForGood: Int
    /// Until when Undo restore works.
    public var undoUntil: Date?

    public init(counts: BackupCounts, added: Int, conflicts: Int, deletedForGood: Int, undoUntil: Date?) {
        self.counts = counts
        self.added = added
        self.conflicts = conflicts
        self.deletedForGood = deletedForGood
        self.undoUntil = undoUntil
    }
}

/// The safety copy from the last restore.
public struct UndoRestore: Hashable, Sendable {
    public var takenAt: Date
    public var until: Date

    public init(takenAt: Date, until: Date) {
        self.takenAt = takenAt
        self.until = until
    }
}

/// Why an export, a check or a restore stopped. Nothing in the app changed in any of them.
public enum BackupError: Error, Hashable, Sendable {
    /// "That passphrase doesn't open this copy."
    case wrongPassphrase
    /// The file isn't a Nifty Outfit Nook copy.
    case notABackup
    /// Changed, cut short or incomplete: a check failed.
    case damaged
    /// Made by a newer version of the app.
    case newerVersion
    /// Not enough free space; `needed` bytes are needed.
    case notEnoughSpace(needed: Int64)
    case passphrase(PassphraseProblem)
    /// No checked copy is waiting (staging was cleared), or there's nothing to undo.
    case nothingToRestore
    /// Anything else. Try again.
    case failed
}

/// Why a passphrase she typed can't be used.
public enum PassphraseProblem: Hashable, Sendable {
    case tooShort
    case doesntMatch
}

/// The passphrase rules (0004 section 3, decision 9): her own of at least 12 characters, typed
/// twice, or a generated one of 24 letters and digits from an alphabet with nothing to confuse
/// (no 0 and O, 1 and I), in groups of four: about 120 bits.
public enum BackupPassphrase {
    public static let minimumLength = 12
    public static let generatedLength = 24
    /// 32 symbols, so each random byte's low five bits pick one with no bias.
    public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// A passphrase from random bytes, one symbol per byte, in groups of four with hyphens.
    public static func generated(from bytes: [UInt8]) -> String {
        let symbols = bytes.prefix(generatedLength).map { alphabet[Int($0 & 31)] }
        return stride(from: 0, to: symbols.count, by: 4)
            .map { String(symbols[$0..<min($0 + 4, symbols.count)]) }
            .joined(separator: "-")
    }

    /// What's wrong with her own passphrase, or `nil` when it can be used. Spaces at the ends
    /// count: the passphrase is used exactly as typed.
    public static func problem(_ passphrase: String, confirmation: String) -> PassphraseProblem? {
        if passphrase.count < minimumLength { return .tooShort }
        if passphrase != confirmation { return .doesntMatch }
        return nil
    }
}
