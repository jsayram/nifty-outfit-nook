import Foundation
import Models

/// The words on the iCloud screen (decision 0004 §5, the 19b wording in
/// `closet/compliance/IN_APP_PRIVACY_TEXT.md`, finished there).
nonisolated enum ICloudText {
    static var title: String {
        String(localized: "iCloud", bundle: .module, comment: "iCloud: screen title and its row")
    }

    static var rowDetail: String {
        String(
            localized: "Keep a copy of your closet in your private iCloud", bundle: .module,
            comment: "Privacy and terms: the line under iCloud")
    }

    static var lede: String {
        String(
            localized: "Your closet, photos and looks in your private iCloud, on your other devices too.",
            bundle: .module, comment: "iCloud: the line under the title")
    }

    static var switchTitle: String {
        String(localized: "Keep a copy in iCloud", bundle: .module, comment: "iCloud: the sync switch")
    }

    static func switchDetail(isOn: Bool) -> String {
        isOn
            ? String(
                localized: "On. Only your Apple Account can reach it; we can’t.", bundle: .module,
                comment: "iCloud: under the switch when sync is on")
            : String(
                localized:
                    "Sync is off. This iPhone keeps everything. Your iCloud copy stays until you delete it in Delete my data.",
                bundle: .module, comment: "iCloud: under the switch when sync is off")
    }

    // MARK: Turning it on and off

    static var turnOnTitle: String {
        String(localized: "Keep a copy in your iCloud?", bundle: .module, comment: "Turn on iCloud: question")
    }

    /// F1 (D11): body data goes too, unless the build uses decision 2's fallback.
    static func turnOnMessage(bytes: Int64, includesBodyData: Bool) -> String {
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let message = String(
            localized: """
                Your closet, photos and looks go to your private iCloud, so they’re on your other devices and come back if you change iPhones. Only your Apple Account can reach it; we can’t.

                Apple can read most iCloud data unless you’ve turned on Advanced Data Protection in Settings. With it on, everything the app puts in iCloud is end-to-end encrypted, apart from the names of record types and their dates and sizes.

                It uses your iCloud storage. About \(size) now.
                """,
            bundle: .module, comment: "Turn on iCloud: what it means. The size is like 1.4 GB")
        return message + "\n\n" + (includesBodyData ? bodyDataGoes : bodyDataStays)
    }

    static var bodyDataGoes: String {
        String(
            localized: "Your measurements, weight, fit notes and try-on photo go too, kept apart from the rest.",
            bundle: .module, comment: "Turn on iCloud: body data is synced too (D11)")
    }

    static var turnOn: String {
        String(localized: "Turn on sync", bundle: .module, comment: "Turn on iCloud: confirm")
    }

    static var notNow: String {
        String(localized: "Not now", bundle: .module, comment: "Turn on iCloud: cancel")
    }

    static var turnOffTitle: String {
        String(localized: "Turn off iCloud for this iPhone?", bundle: .module, comment: "Turn off iCloud: question")
    }

    static var turnOffMessage: String {
        String(
            localized: "Either way, everything stays on this iPhone.", bundle: .module,
            comment: "Turn off iCloud: under the question")
    }

    static var keepCopy: String {
        String(localized: "Keep my iCloud copy", bundle: .module, comment: "Turn off iCloud: other devices carry on")
    }

    static var deleteCopy: String {
        String(
            localized: "Also delete my iCloud copy", bundle: .module,
            comment: "Turn off iCloud: delete the copy in iCloud too")
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Turn off iCloud: cancel")
    }

    static func turnOnProblem(_ result: ICloudTurnOnResult) -> String? {
        switch result {
        case .on: nil
        case .noAccount:
            String(
                localized: "Sign in to iCloud in Settings first.", bundle: .module,
                comment: "Turn on iCloud: no iCloud account on the device")
        case .deletionPending:
            String(
                localized: "Your iCloud copy is still being deleted. Sync can come back once that’s done.",
                bundle: .module, comment: "Turn on iCloud: Delete my data hasn't finished in iCloud")
        case .offline:
            String(
                localized: "iCloud can’t be reached right now. Try again when you’re online.", bundle: .module,
                comment: "Turn on iCloud: offline")
        }
    }

    // MARK: Status (PRD 15.1: never "Synced" while anything is waiting)

    static var statusHeader: String {
        String(localized: "Where your closet is", bundle: .module, comment: "iCloud: header over the status")
    }

    static var savedHere: String {
        String(localized: "Saved on this iPhone", bundle: .module, comment: "iCloud: status, always true")
    }

    static func waiting(changes: Int, photos: Int) -> String {
        String(
            localized: "Waiting to upload: \(changes) changes and \(photos) photos", bundle: .module,
            comment: "iCloud: status while changes wait")
    }

    static var allUploaded: String {
        String(localized: "Everything here is in iCloud", bundle: .module, comment: "iCloud: status, nothing waiting")
    }

    static func lastConfirmed(_ date: Date) -> String {
        let time = date.formatted(date: .abbreviated, time: .shortened)
        return String(
            localized: "Last confirmed by iCloud: \(time)", bundle: .module, comment: "iCloud: status, a date and time")
    }

    static func problem(_ problem: ICloudProblem) -> String {
        switch problem {
        case .offline:
            String(
                localized: "Couldn’t upload: iCloud can’t be reached right now. It tries again on its own.",
                bundle: .module, comment: "iCloud: status when offline")
        case .storageFull:
            String(
                localized:
                    "Your iCloud storage is full. Changes are safe on this iPhone and will upload when there’s space.",
                bundle: .module, comment: "iCloud: status when her iCloud storage is full")
        case .tooLarge(let count):
            String(
                localized: "Couldn’t upload \(count) records: too big for iCloud. They stay on this iPhone.",
                bundle: .module, comment: "iCloud: status when records are over CloudKit's size limit")
        }
    }

    static var tryAgain: String {
        String(localized: "Try again", bundle: .module, comment: "iCloud: send what's waiting now")
    }

    static var openSettings: String {
        String(localized: "Open Settings", bundle: .module, comment: "iCloud: storage full, opens Settings")
    }

    static func conflicts(_ count: Int) -> String {
        String(
            localized: "\(count) changes kept for review: your devices changed the same thing.", bundle: .module,
            comment: "iCloud: values kept after a sync conflict")
    }

    static func newerVersion(_ count: Int) -> String {
        String(
            localized: "Update the app to see \(count) changes from your other device.", bundle: .module,
            comment: "iCloud: records from a newer app version, kept and not shown yet")
    }

    static var reuploaded: String {
        String(
            localized: "Your iCloud encryption was reset, so the app uploaded this iPhone’s closet again.",
            bundle: .module, comment: "iCloud: after an encrypted data reset")
    }

    static var bodyDataStays: String {
        String(
            localized: "Your measurements, weight, fit notes and try-on photo stay on this iPhone.", bundle: .module,
            comment: "iCloud: body data isn't synced")
    }

    static var help: String {
        String(
            localized:
                "iCloud keeps your devices the same. It isn’t a history: a piece you delete is deleted everywhere. For a copy you can go back to, export one in Backups.",
            bundle: .module, comment: "iCloud: what sync is and isn't")
    }

    // MARK: When iCloud changed under the app (0004's table)

    static func pause(_ pause: ICloudPause) -> String {
        switch pause {
        case .signedOut:
            String(
                localized:
                    "You’re signed out of iCloud. Your closet stays on this iPhone and syncs again when you sign back in.",
                bundle: .module, comment: "iCloud: signed out")
        case .differentAccount:
            String(
                localized:
                    "This closet belongs to a different iCloud account. Keep it on this iPhone only, or copy it to the account signed in now?",
                bundle: .module, comment: "iCloud: a different iCloud account is signed in")
        case .removedInSettings:
            String(
                localized: "Your Nifty Outfit Nook data was removed from iCloud in Settings.", bundle: .module,
                comment: "iCloud: she deleted the app's iCloud data in Settings")
        case .turnedOffElsewhere:
            String(
                localized: "iCloud was turned off on another device. This iPhone keeps its closet.", bundle: .module,
                comment: "iCloud: another device turned sync off and deleted the copy")
        case .deletedElsewhere:
            String(
                localized: "Your data was deleted from iCloud on another device. Delete it from this iPhone too?",
                bundle: .module, comment: "iCloud: Delete my data on another device")
        }
    }

    static func choice(_ choice: ICloudChoice, in pause: ICloudPause) -> String {
        switch choice {
        case .keepOnThisDevice:
            pause == .turnedOffElsewhere
                ? String(localized: "OK", bundle: .module, comment: "iCloud: acknowledge, sync off")
                : String(
                    localized: "Keep it on this iPhone (sync off)", bundle: .module,
                    comment: "iCloud: keep the closet here, sync off")
        case .copyToThisAccount:
            String(
                localized: "Copy it to this account", bundle: .module,
                comment: "iCloud: upload this closet to the account signed in now")
        case .uploadAgain:
            String(localized: "Upload it again", bundle: .module, comment: "iCloud: upload this closet again")
        case .deleteHereToo:
            String(localized: "Delete it here too", bundle: .module, comment: "iCloud: erase this device's closet")
        }
    }

    static func deleting(waitingForAccount: Bool) -> String {
        waitingForAccount
            ? String(
                localized:
                    "Your iCloud copy is waiting to be deleted. Sign in to iCloud with the account that held it, or delete it in Settings > your name > iCloud > Storage.",
                bundle: .module, comment: "iCloud: Delete my data waits for the right account")
            : String(
                localized: "Your iCloud copy is deleted the next time this iPhone is online.", bundle: .module,
                comment: "iCloud: Delete my data waits for a connection")
    }
}
