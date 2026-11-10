#if DEBUG
    import Foundation
    import Models

    /// N4, debug builds only: a photo handed back in place of the system photo picker, which UI
    /// tests and capture runs can't drive. With `-fake-picked-photo <name>` the app sets it at launch
    /// to a garment photo from the sample wardrobe (never a person), and every "Choose from Photos"
    /// gets it at once.
    public enum DebugPickedPhoto {
        public static let launchArgument = "-fake-picked-photo"
        /// The photo's bytes, or nil to open the system picker as usual.
        public static var data: Data?
    }

    /// N4, debug builds only: a backup file handed back in place of the Files picker. With
    /// `-fake-picked-backup sample`, Check a copy and Restore from a copy get a fresh export of her
    /// closet, locked with `passphrase`; with `-fake-picked-backup junk`, a file that isn't a copy.
    enum DebugPickedBackup {
        static let launchArgument = "-fake-picked-backup"
        /// The sample copy's passphrase. A test value for this debug hook, not a secret.
        static let passphrase = "debug copy passphrase"

        /// `sample` or `junk`, or nil without the flag.
        static var kind: String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: launchArgument), arguments.indices.contains(index + 1)
            else { return nil }
            return arguments[index + 1]
        }

        /// The file to open.
        static func file(using service: any BackupService) async -> URL? {
            switch kind {
            case "sample":
                return try? await service.export(passphrase: passphrase).url
            case "junk":
                let url = FileManager.default.temporaryDirectory.appending(path: "Not a copy.nookbackup")
                try? Data("This is not a Nifty Outfit Nook copy.".utf8).write(to: url, options: .atomic)
                return url
            default:
                return nil
            }
        }
    }
#endif
