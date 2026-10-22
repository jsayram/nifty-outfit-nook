#if DEBUG
    import Foundation

    /// One file or folder the Device checks screen (debug builds only) reads the Data Protection
    /// class of, with what it should be and what it is.
    public struct FileCheckRow: Identifiable, Hashable, Sendable {
        public enum Verdict: String, Hashable, Sendable {
            case pass = "PASS"
            case fail = "FAIL"
            /// Nothing is there yet (no safety copy made, no export running), so nothing to check.
            case notPresent = "NOT THERE"
            /// The file is there but the system gave no class for it.
            case notReported = "NO CLASS"
        }

        public var id: String { label }
        /// A fixed name for the file or folder, never a path with her photo names in it.
        public let label: String
        public let verdict: Verdict
        /// What the class should be, for example `NSFileProtectionComplete`.
        public let expected: String
        /// What the system reported, if anything.
        public let actual: String?
        /// Left out of device backups: what it should be, and what it is. `nil` where the design
        /// doesn't say.
        public let expectedExcluded: Bool?
        public let actualExcluded: Bool?
        /// Extra words, such as "12 files, all NSFileProtectionComplete".
        public let detail: String?

        public init(
            label: String, verdict: Verdict, expected: String, actual: String?, expectedExcluded: Bool?,
            actualExcluded: Bool?, detail: String? = nil
        ) {
            self.label = label
            self.verdict = verdict
            self.expected = expected
            self.actual = actual
            self.expectedExcluded = expectedExcluded
            self.actualExcluded = actualExcluded
            self.detail = detail
        }

        /// The one-line answer: how many passed, failed or weren't there.
        public static func summary(_ rows: [FileCheckRow]) -> String {
            func count(_ verdict: Verdict) -> Int { rows.filter { $0.verdict == verdict }.count }
            let failed = count(.fail)
            let head = failed > 0 ? "FAIL" : (count(.pass) > 0 ? "PASS" : "NOTHING CHECKED")
            var text = "\(head): \(count(.pass)) passed, \(failed) failed, \(count(.notPresent)) not there yet"
            if count(.notReported) > 0 { text += ", \(count(.notReported)) with no class reported" }
            return text
        }
    }

    /// What the Device checks screen shows, read through closures so the screen needn't know about
    /// the store or the files. The app builds one (`DeviceChecksSource.make` in Services).
    public struct DeviceChecksSource: Sendable {
        /// Starts the lock probe. Called once when the screen appears.
        public var begin: @Sendable @MainActor () -> Void
        public var deviceLines: @Sendable () -> [String]
        public var fileRows: @Sendable () -> [FileCheckRow]
        public var storeLines: @Sendable () -> [String]
        public var lockLines: @Sendable () -> [String]

        public init(
            begin: @escaping @Sendable @MainActor () -> Void, deviceLines: @escaping @Sendable () -> [String],
            fileRows: @escaping @Sendable () -> [FileCheckRow], storeLines: @escaping @Sendable () -> [String],
            lockLines: @escaping @Sendable () -> [String]
        ) {
            self.begin = begin
            self.deviceLines = deviceLines
            self.fileRows = fileRows
            self.storeLines = storeLines
            self.lockLines = lockLines
        }
    }
#endif
