import Foundation
import Models

/// The words on Backups and its sheets (0004 sections 3 and 4, in plain language).
nonisolated enum BackupsText {
    static var title: String {
        String(localized: "Backups", bundle: .module, comment: "Backups: screen title and its row")
    }

    static var lede: String {
        String(
            localized: "A copy of your closet in one file, locked with a passphrase. Keep it somewhere safe.",
            bundle: .module, comment: "Backups: the line under the title")
    }

    static var rowDetail: String {
        String(
            localized: "Export a copy, or restore one", bundle: .module,
            comment: "Privacy and terms and Profile: the line under Backups")
    }

    // MARK: Export

    static var exportTitle: String {
        String(localized: "Export a copy", bundle: .module, comment: "Backups: export row and sheet title")
    }

    static var exportDetail: String {
        String(
            localized:
                "Everything in the app, in one file, locked with a passphrase you choose. It doesn’t update itself: export again to keep it current.",
            bundle: .module, comment: "Backups: what Export a copy does")
    }

    static var whatGoesHeader: String {
        String(localized: "What goes in it", bundle: .module, comment: "Export a copy: header over the counts")
    }

    static var bodyData: String {
        String(
            localized: "Your measurements and weight", bundle: .module,
            comment: "Export a copy: named on its own line, as the most sensitive part")
    }

    static var tryOnPhoto: String {
        String(localized: "Your try-on photo", bundle: .module, comment: "Export a copy: the try-on photo goes too")
    }

    static func estimatedSize(_ bytes: Int64) -> String {
        let size = bytes.formatted(.byteCount(style: .file))
        return String(
            localized: "About \(size)", bundle: .module, comment: "Export a copy: the file's estimated size")
    }

    static var makeOne: String {
        String(localized: "Make one for me", bundle: .module, comment: "Export a copy: generated passphrase choice")
    }

    static var useMine: String {
        String(localized: "Use my own", bundle: .module, comment: "Export a copy: her own passphrase choice")
    }

    static var cantRecover: String {
        String(
            localized:
                "We can’t recover this passphrase. Without it, nobody can open the file, including you. Write it down or save it in Passwords.",
            bundle: .module, comment: "Export a copy: the warning about the passphrase")
    }

    static var copyPassphrase: String {
        String(localized: "Copy passphrase", bundle: .module, comment: "Export a copy: copies the generated passphrase")
    }

    static var copied: String {
        String(
            localized: "Copied for 2 minutes, on this iPhone only", bundle: .module,
            comment: "Toast after copying the passphrase")
    }

    static var passphraseField: String {
        String(localized: "Passphrase", bundle: .module, comment: "Export a copy: her own passphrase field")
    }

    static var confirmField: String {
        String(localized: "Type it again", bundle: .module, comment: "Export a copy: confirm passphrase field")
    }

    static func problem(_ problem: PassphraseProblem) -> String {
        switch problem {
        case .tooShort:
            String(
                localized: "Use at least \(BackupPassphrase.minimumLength) characters.", bundle: .module,
                comment: "Export a copy: her passphrase is too short")
        case .doesntMatch:
            String(
                localized: "The two don’t match yet.", bundle: .module,
                comment: "Export a copy: the passphrase and its confirmation differ")
        }
    }

    static var exportButton: String {
        String(localized: "Export", bundle: .module, comment: "Export a copy: the button that makes the file")
    }

    static var exporting: String {
        String(localized: "Making your copy…", bundle: .module, comment: "Export a copy: while the file is written")
    }

    static func exported(_ name: String) -> String {
        String(
            localized:
                "Your copy is saved as “\(name)”. It holds your measurements and photos; keep the passphrase somewhere safe.",
            bundle: .module, comment: "Export a copy: done, with the file name")
    }

    static var checkThisCopy: String {
        String(localized: "Check this copy", bundle: .module, comment: "Export a copy: done, check the file opens")
    }

    // MARK: Check and Restore

    static var checkTitle: String {
        String(localized: "Check a copy", bundle: .module, comment: "Backups: check row and sheet title")
    }

    static var checkDetail: String {
        String(
            localized: "Makes sure a copy opens with its passphrase. Changes nothing.", bundle: .module,
            comment: "Backups: what Check a copy does")
    }

    static var restoreTitle: String {
        String(localized: "Restore from a copy", bundle: .module, comment: "Backups: restore row and sheet title")
    }

    static var restoreDetail: String {
        String(
            localized: "Brings back a closet from a copy you exported. You see what’s in it first.", bundle: .module,
            comment: "Backups: what Restore from a copy does")
    }

    static var restoreFromFile: String {
        String(
            localized: "Restore from a backup file", bundle: .module,
            comment: "Onboarding: the welcome's button to restore a copy on a new iPhone")
    }

    static var unlockLine: String {
        String(
            localized: "Type the passphrase you chose when you exported it.", bundle: .module,
            comment: "Check or Restore: asking for the copy's passphrase")
    }

    static var open: String {
        String(localized: "Open", bundle: .module, comment: "Check or Restore: opens the copy with the passphrase")
    }

    static var checking: String {
        String(localized: "Checking every file in the copy…", bundle: .module, comment: "Check or Restore: working")
    }

    static var wrongPassphrase: String {
        String(
            localized: "That passphrase doesn’t open this copy.", bundle: .module,
            comment: "Check or Restore: the passphrase is wrong")
    }

    static func copyFrom(_ date: Date) -> String {
        let day = date.formatted(.dateTime.day().month(.wide))
        return String(
            localized: "This copy is from \(day). Anything you added or changed after that isn’t in it.",
            bundle: .module, comment: "Restore preview: the copy's date")
    }

    static var inCopyHeader: String {
        String(localized: "In the copy", bundle: .module, comment: "Restore preview: header over the copy's counts")
    }

    static var onPhoneHeader: String {
        String(
            localized: "On this iPhone now", bundle: .module, comment: "Restore preview: header over the phone's counts"
        )
    }

    static var copyWorks: String {
        String(
            localized: "This copy works. Every file in it opened and matched.", bundle: .module,
            comment: "Check a copy: it passed")
    }

    static func deletedForGood(_ count: Int) -> String {
        String(
            localized: "\(count) pieces in it were deleted for good, so they stay deleted.", bundle: .module,
            comment: "Restore preview: pieces that won't come back")
    }

    static func missing(_ count: Int) -> String {
        String(
            localized: "\(count) things in it point to a piece or photo it doesn’t have. They show as missing.",
            bundle: .module, comment: "Restore preview: references that don't resolve")
    }

    static var replace: String {
        String(
            localized: "Replace my closet with this copy", bundle: .module,
            comment: "Restore preview: the Replace button")
    }

    static var replaceDetail: String {
        String(
            localized: "For a new iPhone, or to go back. What’s here now is kept for 7 days, so you can undo.",
            bundle: .module, comment: "Restore preview: under Replace")
    }

    static var addMissing: String {
        String(
            localized: "Add what’s missing", bundle: .module, comment: "Restore preview: the Add what's missing button")
    }

    static var addMissingDetail: String {
        String(
            localized:
                "Adds pieces, looks and suitcases you don’t have here. Nothing here is removed or changed; where a piece differs, this iPhone’s version stays.",
            bundle: .module, comment: "Restore preview: under Add what's missing")
    }

    static var askReplaceTitle: String {
        String(localized: "Replace your closet?", bundle: .module, comment: "Restore: confirm Replace, title")
    }

    static var askReplaceMessage: String {
        String(
            localized:
                "Everything on this iPhone now is replaced by the copy. You can undo it from Backups for 7 days.",
            bundle: .module, comment: "Restore: confirm Replace, message")
    }

    static var restoring: String {
        String(localized: "Restoring your closet…", bundle: .module, comment: "Restore: working")
    }

    static var restored: String {
        String(localized: "Your closet is restored", bundle: .module, comment: "Restore: done, title")
    }

    static func conflicts(_ count: Int) -> String {
        String(
            localized: "\(count) things were different in the copy. This iPhone’s versions stayed.", bundle: .module,
            comment: "Restore: done, conflicts kept for review")
    }

    static func undoUntil(_ date: Date) -> String {
        let day = date.formatted(.dateTime.day().month(.wide))
        return String(
            localized: "You can undo this from Backups until \(day).", bundle: .module,
            comment: "Restore: done, how long Undo restore lasts")
    }

    static var done: String {
        String(localized: "Done", bundle: .module, comment: "Backups: closes a finished sheet")
    }

    // MARK: Undo

    static var undoTitle: String {
        String(localized: "Undo restore", bundle: .module, comment: "Backups: undo row and question")
    }

    static func undoDetail(_ undo: UndoRestore) -> String {
        let taken = undo.takenAt.formatted(.dateTime.day().month(.wide))
        let until = undo.until.formatted(.dateTime.day().month(.wide))
        return String(
            localized: "Puts back your closet as it was before the restore on \(taken). Possible until \(until).",
            bundle: .module, comment: "Backups: what Undo restore does, with dates")
    }

    static var askUndoMessage: String {
        String(
            localized:
                "Your closet goes back to how it was before the restore. Pieces deleted for good since stay deleted.",
            bundle: .module, comment: "Backups: confirm Undo restore")
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Backups: cancel a question")
    }

    // MARK: Problems

    static func failed(_ error: BackupError) -> String {
        switch error {
        case .wrongPassphrase: wrongPassphrase
        case .notABackup:
            String(
                localized: "That file isn’t a Nifty Outfit Nook copy.", bundle: .module,
                comment: "Backups: the picked file isn't a backup")
        case .damaged:
            String(
                localized: "This copy is damaged or incomplete, so nothing was restored.", bundle: .module,
                comment: "Backups: the copy failed a check")
        case .newerVersion:
            String(
                localized: "This copy is from a newer version of Nifty Outfit Nook. Update the app, then try again.",
                bundle: .module, comment: "Backups: the copy is from a newer app")
        case .notEnoughSpace(let needed):
            String(
                localized:
                    "There isn’t enough space on this iPhone. It needs \(needed.formatted(.byteCount(style: .file))) free.",
                bundle: .module, comment: "Backups: not enough free space, with the amount needed")
        case .passphrase(let issue): Self.problem(issue)
        case .nothingToRestore:
            String(
                localized: "That copy isn’t open any more. Pick it again.", bundle: .module,
                comment: "Backups: the checked copy was cleared")
        case .failed:
            String(
                localized: "That didn’t work, and nothing changed. Try again.", bundle: .module,
                comment: "Backups: something else went wrong")
        }
    }

    static var nowhereElse: String {
        String(
            localized:
                "The app sends your copy nowhere. You choose where it’s saved, and only you have the passphrase.",
            bundle: .module, comment: "Backups: note at the bottom")
    }
}
