#if DEBUG
    import Foundation
    import Synchronization

    /// Debug builds only (N4): holds a loading state on screen, or makes one operation fail, so every
    /// loading and error state can be reached on demand and screenshotted.
    ///
    /// - `-hold <scope>[,<scope>...]`: the matching fake waits until its task is cancelled, so the
    ///   spinner or loading screen stays.
    /// - `-fail <scope>[=<variant>][,...]`: the matching fake fails. The variant picks the error where
    ///   a fake has more than one (`-fail send=offline`); without one, each fake fails its plainest way.
    /// - `-faults-wait`: nothing holds or fails until the Darwin notification `armNotification` is
    ///   posted, so a screen can load first and then fail on its next read. From a Mac:
    ///   `xcrun simctl spawn <udid> notifyutil -p com.jsayram.niftyoutfitnook.debug.faults`.
    ///
    /// The fakes ask with their own scopes. A store call asks with `<store>.<method>`, `<store>-load` or
    /// `<store>-save`, `store-load` or `store-save`, and `<store>` (see `storeScopes`). Every check
    /// also matches `all`. Each fake's comment names its own scope.
    public struct DebugFaults: Hashable, Sendable {
        public static let holdArgument = "-hold"
        public static let failArgument = "-fail"
        public static let waitArgument = "-faults-wait"
        /// Posting this Darwin notification arms faults launched with `-faults-wait`.
        public static let armNotification = "com.jsayram.niftyoutfitnook.debug.faults"

        /// Scopes that hold.
        public var holds: Set<String>
        /// Scopes that fail, each with its variant ("" when none was given).
        public var fails: [String: String]
        /// Faults wait for `armNotification`.
        public var waitsForSignal: Bool

        public init(holds: Set<String> = [], fails: [String: String] = [:], waitsForSignal: Bool = false) {
            self.holds = holds
            self.fails = fails
            self.waitsForSignal = waitsForSignal
        }

        /// Reads every `-hold` and `-fail` in the arguments (each may come more than once) and
        /// `-faults-wait`. Empty scopes are ignored.
        public init(arguments: [String]) {
            self.init(waitsForSignal: arguments.contains(Self.waitArgument))
            for (index, argument) in arguments.enumerated() where arguments.indices.contains(index + 1) {
                let entries = arguments[index + 1].split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                switch argument {
                case Self.holdArgument:
                    holds.formUnion(entries.filter { !$0.isEmpty })
                case Self.failArgument:
                    for entry in entries where !entry.isEmpty {
                        let pair = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(
                            String.init)
                        guard let scope = pair.first, !scope.isEmpty else { continue }
                        fails[scope] = pair.count == 2 ? pair[1] : ""
                    }
                default:
                    continue
                }
            }
        }

        /// No faults: what every build without the flags runs with.
        public static let none = DebugFaults()

        /// This launch's faults.
        public static let current = DebugFaults(arguments: ProcessInfo.processInfo.arguments)

        public var isEmpty: Bool { holds.isEmpty && fails.isEmpty }

        /// A failure that matched: the scope and the variant asked for (nil when none was given).
        public struct Failure: Hashable, Sendable {
            public var scope: String
            public var variant: String?

            public init(scope: String, variant: String?) {
                self.scope = scope
                self.variant = variant
            }
        }

        /// What a fake should do.
        public enum Fault: Hashable, Sendable {
            case fail(Failure)
            /// It held, and its task was cancelled.
            case cancelled
        }

        /// Whether faults apply yet: always, unless launched with `-faults-wait` and not armed.
        public var isArmed: Bool { !waitsForSignal || Self.signal.withLock { $0 } }

        /// Holds while a hold matches `scopes` (until the task is cancelled), then returns the failure
        /// that matches, if any. `nil`: carry on as normal.
        public func fault(for scopes: [String]) async -> Fault? {
            guard !isEmpty, isArmed else { return nil }
            let scopes = scopes + ["all"]
            if scopes.contains(where: holds.contains) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3_600))
                }
                return .cancelled
            }
            return failure(for: scopes).map(Fault.fail)
        }

        /// The failure that matches `scopes` now, without holding, for fakes that can't wait.
        public func failure(for scopes: [String]) -> Failure? {
            guard !fails.isEmpty, isArmed else { return nil }
            for scope in scopes + ["all"] {
                if let variant = fails[scope] { return Failure(scope: scope, variant: variant.isEmpty ? nil : variant) }
            }
            return nil
        }

        // MARK: Stores

        /// The method names that read; every other store call writes.
        static let readMethods: Set<String> = [
            "garments", "garment", "looks", "look", "suitcases", "suitcase", "profile", "drafts", "draft",
            "pictures", "picture", "progress", "state",
        ]

        /// The scopes a store call answers to, most specific first: `closet.garment`, `closet-load`,
        /// `store-load`, `closet`. `method` is `#function`, such as `garment(_:)`.
        public static func storeScopes(store: String, method: String) -> [String] {
            let name = String(method.prefix { $0 != "(" })
            let kind = readMethods.contains(name) ? "load" : "save"
            return ["\(store).\(name)", "\(store)-\(kind)", "store-\(kind)", store]
        }

        // MARK: Arming

        private static let signal = Mutex(false)

        /// Arms faults launched with `-faults-wait`, as the Darwin notification does.
        public static func arm() {
            signal.withLock { $0 = true }
        }

        /// For tests: back to not armed.
        public static func disarm() {
            signal.withLock { $0 = false }
        }

        /// Starts listening for `armNotification`. Called once at launch.
        public static func listenForArming() {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in DebugFaults.arm() },
                armNotification as CFString, nil, .deliverImmediately)
        }
    }
#endif
