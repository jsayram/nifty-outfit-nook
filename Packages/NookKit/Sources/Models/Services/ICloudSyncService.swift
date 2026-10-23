import Foundation

// Private iCloud sync (decision 0004 §5), as the screens see it.
//
// Built against a stand-in CloudKit in Phase 21b and kept off: the iCloud row only appears in a
// build made with `NOOK_ICLOUD = YES` (docs/icloud.md), once Jose has made the iCloud container
// and the test accounts. The real engine is `ICloudSync` in Services.

/// Turning sync on and off, what it's doing, and her answers when iCloud changed under the app.
public protocol ICloudSyncService: ICloudCopyDeletion {
    /// Where sync stands now, for the iCloud screen.
    func status() async -> ICloudSyncStatus
    /// "Turn on sync": binds this closet to the iCloud account signed in now, merges with any copy
    /// already there by ID, then uploads.
    func turnOn() async -> ICloudTurnOnResult
    /// "Turn off iCloud for this iPhone". The data on this iPhone always stays. With
    /// `deletingCopy`, the iCloud copy is deleted too and her other devices are told why.
    func turnOff(deletingCopy: Bool) async -> DeletionOutcome
    /// Her answer to the question the status asks (`ICloudSyncStatus.State.paused`).
    func answer(_ choice: ICloudChoice) async
    /// Try again: looks for changes here and in iCloud, and sends what's waiting.
    func syncNow() async
}

/// What the iCloud screen shows (0004 "Status she sees" and "When iCloud changes under the app").
public struct ICloudSyncStatus: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// Never turned on, or turned off. Everything stays on this iPhone.
        case off
        case on
        /// Stopped until she answers, or until iCloud is back.
        case paused(ICloudPause)
        /// Delete my data asked for the iCloud copy to go and iCloud hasn't confirmed it yet.
        /// `waitingForAccount` when a different iCloud account is signed in now.
        case deletingCopy(waitingForAccount: Bool)
    }

    public var state: State
    /// Records changed here that iCloud hasn't confirmed yet.
    public var waitingChanges: Int
    /// Photos not uploaded yet.
    public var waitingPhotos: Int
    public var problem: ICloudProblem?
    /// When iCloud last confirmed an upload.
    public var lastConfirmed: Date?
    /// Values kept for review after both devices changed the same thing.
    public var conflictsToReview: Int
    /// Records from another device saved by a newer version of the app: kept, never overwritten,
    /// shown after an update. "Update the app to see 3 pieces from your other device."
    public var fromNewerVersion: Int
    public var notice: ICloudNotice?
    /// About how much of her iCloud storage the copy uses.
    public var estimatedBytes: Int64
    /// Whether measurements, weight, fit notes and the try-on photo go to iCloud too. Off while
    /// decision 2 (App Review 5.1.3(ii)) is open.
    public var includesBodyData: Bool

    public init(
        state: State = .off, waitingChanges: Int = 0, waitingPhotos: Int = 0, problem: ICloudProblem? = nil,
        lastConfirmed: Date? = nil, conflictsToReview: Int = 0, fromNewerVersion: Int = 0,
        notice: ICloudNotice? = nil, estimatedBytes: Int64 = 0, includesBodyData: Bool = false
    ) {
        self.state = state
        self.waitingChanges = waitingChanges
        self.waitingPhotos = waitingPhotos
        self.problem = problem
        self.lastConfirmed = lastConfirmed
        self.conflictsToReview = conflictsToReview
        self.fromNewerVersion = fromNewerVersion
        self.notice = notice
        self.estimatedBytes = estimatedBytes
        self.includesBodyData = includesBodyData
    }

    /// Nothing waiting and no problem: the only time the screen may say everything's in iCloud.
    public var isUpToDate: Bool {
        state == .on && waitingChanges == 0 && waitingPhotos == 0 && problem == nil
    }
}

/// Why sync stopped (0004's table of account events). Each has its own words and choices.
public enum ICloudPause: String, Hashable, Sendable, Codable, CaseIterable {
    /// She signed out of iCloud. Syncs again when she signs back in to the same account.
    case signedOut
    /// A different iCloud account is signed in. Never uploads into it unless she says so.
    case differentAccount
    /// She deleted the app's data in Settings > iCloud.
    case removedInSettings
    /// Another device turned sync off and deleted the iCloud copy.
    case turnedOffElsewhere
    /// Another device used Delete my data.
    case deletedElsewhere

    /// Her choices, in the order the screen shows them.
    public var choices: [ICloudChoice] {
        switch self {
        case .signedOut: []
        case .differentAccount: [.keepOnThisDevice, .copyToThisAccount]
        case .removedInSettings: [.keepOnThisDevice, .uploadAgain, .deleteHereToo]
        case .turnedOffElsewhere: [.keepOnThisDevice]
        case .deletedElsewhere: [.deleteHereToo, .keepOnThisDevice]
        }
    }
}

/// An answer to a pause.
public enum ICloudChoice: String, Hashable, Sendable, Codable {
    /// Sync off; this device keeps everything.
    case keepOnThisDevice
    /// Copy this closet into the iCloud account signed in now.
    case copyToThisAccount
    /// Upload this device's closet to iCloud again.
    case uploadAgain
    /// Erase this device's closet too.
    case deleteHereToo
}

/// Why uploads aren't going through. Local saves always carry on.
public enum ICloudProblem: Hashable, Sendable {
    /// No connection, or iCloud unavailable for now. The engine retries on its own.
    case offline
    /// Her iCloud storage is full.
    case storageFull
    /// Records too big for one CloudKit record (1 MB). Kept on this iPhone.
    case tooLarge(Int)
}

/// Something she's told once.
public enum ICloudNotice: String, Hashable, Sendable, Codable {
    /// Her iCloud encryption was reset, so the app uploaded this device's closet again.
    case reuploadedAfterReset
}

/// What "Turn on sync" did.
public enum ICloudTurnOnResult: Hashable, Sendable {
    case on
    /// No iCloud account signed in on this device.
    case noAccount
    /// Delete my data's iCloud deletion hasn't finished; sync can't come back until it has.
    case deletionPending
    /// iCloud couldn't be reached.
    case offline
}
