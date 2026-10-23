import Foundation
import Models

// What sync does when iCloud changes under the app (decision 0004, "When iCloud changes under
// the app"), as a pure state machine, so every row of that table is tested on its own.
//
// The rule the whole table serves: one account's data never uploads into another (PRD 15.1).
// Sync runs only in `.on`, and only while the account signed in is the one the closet belongs to.

/// Whether sync runs. Saved in the store with the rest of sync's bookkeeping.
enum SyncMode: Codable, Hashable, Sendable {
    case off
    case on
    case paused(ICloudPause)
    /// Delete my data or Turn off with Also delete is deleting the iCloud copy.
    case deleting
}

enum SyncPolicy {
    /// Something that changes the mode.
    enum Input: Hashable, Sendable {
        /// The account signed in now, hashed, or `nil` when signed out.
        case account(current: String?)
        /// A zone was deleted on the server. `remote` is the reason in a newer `SyncGeneration`,
        /// when another device wrote one.
        case zoneDeleted(SyncZoneDeletionReason, remote: SyncGeneration.Reason?)
        /// Her answer, with the account signed in now.
        case choice(ICloudChoice, current: String?)
    }

    enum Action: Hashable, Sendable {
        /// Start syncing again: zones, pending changes, a fetch.
        case resume
        /// Stop sending; local data stays.
        case stop
        /// Forget what the server had (change tags, ancestors), make the zones again and upload
        /// everything on this device as new, merging by ID with whatever is there.
        case reuploadEverything
        /// The iCloud copy is gone for good: forget what the server had.
        case forgetServer
        /// Erase this device's closet, as Delete my data does.
        case eraseThisDevice
    }

    struct State: Hashable, Sendable {
        var mode: SyncMode
        /// The hashed iCloud account this closet belongs to.
        var closetAccount: String?
    }

    static func next(_ state: State, _ input: Input) -> (State, [Action]) {
        var state = state
        switch input {
        case .account(let current):
            switch state.mode {
            case .off, .deleting, .paused(.removedInSettings), .paused(.turnedOffElsewhere),
                .paused(.deletedElsewhere):
                // Off stays off; a deletion finishes on its own terms; a question stays asked.
                return (state, [])
            case .on, .paused(.signedOut), .paused(.differentAccount):
                guard let current else {
                    let wasOn = state.mode == .on
                    state.mode = .paused(.signedOut)
                    return (state, wasOn ? [.stop] : [])
                }
                if current == state.closetAccount {
                    let resumes = state.mode != .on
                    state.mode = .on
                    return (state, resumes ? [.resume] : [])
                }
                // A different account: pause, and never upload into it unless she says so.
                state.mode = .paused(.differentAccount)
                return (state, [.stop])
            }

        case .zoneDeleted(let reason, let remote):
            guard state.mode == .on || state.mode == .paused(.signedOut) else { return (state, []) }
            switch reason {
            case .encryptedDataReset:
                // Apple's guidance: delete and make the zones again, and upload what's here.
                state.mode = .on
                return (state, [.reuploadEverything])
            case .purged:
                state.mode = .paused(.removedInSettings)
            case .deleted:
                state.mode = .paused(remote == .deletedEverything ? .deletedElsewhere : .turnedOffElsewhere)
            }
            return (state, [.stop])

        case .choice(let choice, let current):
            guard case .paused(let pause) = state.mode, pause.choices.contains(choice) else { return (state, []) }
            switch (pause, choice) {
            case (.differentAccount, .copyToThisAccount):
                guard let current else { return (state, []) }
                state.mode = .on
                state.closetAccount = current
                return (state, [.reuploadEverything])
            case (.differentAccount, .keepOnThisDevice):
                // Her copy in the other account stays as it was.
                state.mode = .off
                return (state, [.stop])
            case (.removedInSettings, .uploadAgain):
                guard let current, current == state.closetAccount else { return (state, []) }
                state.mode = .on
                return (state, [.reuploadEverything])
            case (_, .deleteHereToo):
                state.mode = .off
                return (state, [.forgetServer, .eraseThisDevice])
            case (_, .keepOnThisDevice):
                state.mode = .off
                return (state, [.forgetServer])
            default:
                return (state, [])
            }
        }
    }
}
