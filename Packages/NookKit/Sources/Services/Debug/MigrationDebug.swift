#if DEBUG
    import Foundation
    import Models
    import SQLite3
    import SwiftData
    import Synchronization
    import os

    /// Helpers for the migration checks on a real iPhone (`closet/DEVICE_TEST_CHECKLIST.md` 2.16).
    /// Debug builds only; none of it is in Release.
    ///
    /// - `-make-old-store` turns her store back into a version 1 store (same records), writes it
    ///   and quits the app, so the next launch has a real migration to do.
    /// - `-migration-kill-at <step>` kills the app (SIGKILL, as a force-quit would) when the
    ///   migration reaches that step. The steps are the ones `SchemaV2MigrationTests` kills at:
    ///   `journal.snapshotting`, `snapshot.copied`, `journal.snapshotTaken`, `journal.migrating`,
    ///   `migration.finished`, `journal.migrated`, `verified`, `journal.verified`. A restore's
    ///   steps (`restore.writing` and so on) work the same way.
    /// - `-migration-pause-at <step> [seconds]` waits at that step (20 seconds by default), so a
    ///   real force-quit from the app switcher can land mid-migration.
    ///
    /// The Device checks screen (`-device-checks`) shows what the last launch did.
    public enum MigrationDebug {
        /// What the last time the store was opened did.
        public struct LastOpen: Sendable, Equatable {
            public struct Step: Sendable, Equatable {
                public let name: String
                public let seconds: Double
            }
            public var seconds: Double
            public var steps: [Step]
            public var migratedFrom: Int?
            public var resumedAfter: String?
            public var snapshotRestored: Bool
            public var problem: String?
        }

        private struct State {
            var killAt: String?
            var pauseAt: String?
            var pauseSeconds = 20.0
            var started: ContinuousClock.Instant?
            var steps: [LastOpen.Step] = []
            var killNeverReached: String?
            var last: LastOpen?
        }

        private static let state = Mutex(State())
        private static let log = Logger(subsystem: "com.jsayram.niftyoutfitnook", category: "device-checks")

        // MARK: Launch arguments

        /// Reads `-migration-kill-at` and `-migration-pause-at`. Call once, first thing at launch.
        public static func install(arguments: [String]) {
            state.withLock {
                $0.killAt = value(after: "-migration-kill-at", in: arguments)
                $0.pauseAt = value(after: "-migration-pause-at", in: arguments)
                if let flag = arguments.firstIndex(of: "-migration-pause-at"), arguments.indices.contains(flag + 2),
                    let seconds = Double(arguments[flag + 2])
                {
                    $0.pauseSeconds = seconds
                }
            }
        }

        private static func value(after flag: String, in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }

        // MARK: Called by the migration

        static func openStarted() {
            state.withLock {
                $0.started = .now
                $0.steps = []
                $0.killNeverReached = nil
            }
        }

        /// A checkpoint was reached: note it, then kill or pause if a launch argument asked.
        static func reached(_ name: String) {
            let action = state.withLock { state -> (kill: Bool, pause: Double?) in
                if let started = state.started {
                    state.steps.append(.init(name: name, seconds: seconds(from: started)))
                }
                return (state.killAt == name, state.pauseAt == name ? state.pauseSeconds : nil)
            }
            if let pause = action.pause {
                log.notice("Pausing \(pause, privacy: .public) s at migration step \(name, privacy: .public)")
                Thread.sleep(forTimeInterval: pause)
            }
            if action.kill {
                log.notice("Killing the app at migration step \(name, privacy: .public)")
                fflush(stdout)
                kill(getpid(), SIGKILL)
            }
        }

        static func openFinished(_ opening: StoreOpening) {
            state.withLock { state in
                guard let started = state.started else { return }
                var last = LastOpen(
                    seconds: seconds(from: started), steps: state.steps, migratedFrom: nil, resumedAfter: nil,
                    snapshotRestored: false, problem: nil)
                switch opening {
                case .ready(_, let report):
                    last.migratedFrom = report.migratedFrom
                    last.resumedAfter = report.resumedAfter?.rawValue
                    last.snapshotRestored = report.snapshotRestored
                case .problem(let problem):
                    last.problem = "\(problem)"
                }
                state.last = last
                state.started = nil
                if let kill = state.killAt, !state.steps.contains(where: { $0.name == kill }) {
                    state.killNeverReached = kill
                }
            }
        }

        private static func seconds(from start: ContinuousClock.Instant) -> Double {
            let elapsed = start.duration(to: .now)
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }

        // MARK: Making an old store

        public enum OldStoreOutcome: Equatable, Sendable {
            case written(records: Int)
            case alreadyOld
            case noStore
            /// A migration was started and not finished. Launch once without arguments first.
            case migrationPending
            case failed
        }

        /// With `-make-old-store`: rewrites her store as a version 1 store, then quits the app. Run
        /// before anything opens the store.
        public static func makeOldStoreIfAsked(arguments: [String], location: StoreLocation) {
            guard arguments.contains("-make-old-store") else { return }
            let outcome = makeOldStore(at: location)
            log.notice("make-old-store: \(String(describing: outcome), privacy: .public). Quitting.")
            fflush(stdout)
            exit(0)
        }

        /// Turns the store at `location` into a version 1 store holding the same records, so the
        /// next open runs the real version 1 to 2 migration. Nothing is changed unless it all worked.
        static func makeOldStore(at location: StoreLocation) -> OldStoreOutcome {
            let coordinator = MigrationCoordinator<NookMigrationPlan>(location: location)
            guard FileManager.default.fileExists(atPath: location.storeURL.path) else { return .noStore }
            if let journal = try? coordinator.readJournal(), journal.step != .verified { return .migrationPending }
            guard let version = coordinator.storedVersion() else { return .failed }
            if version == 1 { return .alreadyOld }
            let temporary = location.directory.appending(path: "Nook-old.store")
            let files = ["", "-wal", "-shm"].map { URL(filePath: temporary.path + $0) }
            defer { for file in files { try? FileManager.default.removeItem(at: file) } }
            do {
                let rows = try StoreSQLite.rowsWithDates(of: location.storeURL)
                try writeVersion1(rows, to: temporary)
                // One file with no log beside it, so it can replace the store file by file.
                try checkpointOnceClosed(temporary)
                for file in location.storeFiles { try? FileManager.default.removeItem(at: file) }
                try FileManager.default.moveItem(at: temporary, to: location.storeURL)
                location.protectStoreFiles()
                return .written(records: rows.count)
            } catch {
                return .failed
            }
        }

        /// SwiftData closes a container's SQLite connection a little after the container goes,
        /// not as it goes (tens of milliseconds on a busy machine), and leaving WAL mode needs
        /// every other connection closed: until then SQLite answers SQLITE_BUSY, and doesn't wait
        /// on a busy timeout for it. So this tries again until the file is free, up to 5 seconds.
        private static func checkpointOnceClosed(_ url: URL) throws {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(5)
            while true {
                do {
                    return try StoreSQLite.checkpoint(url)
                } catch {
                    if clock.now >= deadline { throw error }
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
        }

        private static func writeVersion1(
            _ rows: [(kind: String, key: String, payloadVersion: Int, payload: Data, savedAt: Date)], to url: URL
        ) throws {
            let container = try containerCreation.withLock {
                try ModelContainer(
                    for: Schema(versionedSchema: NookSchemaV1.self),
                    configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
            }
            let context = ModelContext(container)
            for row in rows {
                context.insert(
                    NookSchemaV1.StoredRecord(
                        kind: row.kind, key: row.key, payloadVersion: row.payloadVersion, payload: row.payload,
                        savedAt: row.savedAt))
            }
            try context.save()
        }

        // MARK: What the screen shows

        /// The store, its migration and its last open, in plain lines with no content: counts, a
        /// fingerprint of every record's kind, key and payload hash, versions and times.
        public static func storeLines(location: StoreLocation) -> [String] {
            var lines: [String] = []
            let coordinator = MigrationCoordinator<NookMigrationPlan>(location: location)
            guard FileManager.default.fileExists(atPath: location.storeURL.path) else {
                return ["No store file yet."]
            }
            let current = MigrationCoordinator<NookMigrationPlan>.currentVersion
            lines.append(
                "Store version on disk: \(coordinator.storedVersion().map(String.init) ?? "unknown") (this build writes \(current))"
            )
            if let manifest = try? StoreSQLite.manifest(of: location.storeURL) {
                var kinds: [String: Int] = [:]
                for key in manifest.records.keys {
                    kinds[String(key.prefix { $0 != "/" }), default: 0] += 1
                }
                let counts = kinds.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                lines.append("Records: \(manifest.records.count) (\(counts))")
                let joined = manifest.records.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
                    .joined(separator: "\n")
                lines.append("Fingerprint: \(StoreSQLite.hash(Data(joined.utf8)).prefix(16))")
            } else {
                lines.append("Records: could not be read")
            }
            lines.append("Integrity check: \((try? StoreSQLite.integrityCheck(location.storeURL)) ?? "could not run")")
            if let journal = try? coordinator.readJournal() {
                lines.append(
                    "Journal: step \(journal.step.rawValue), version \(journal.from) to \(journal.to), tries after the first \(journal.attempts)"
                )
            } else {
                lines.append("Journal: none")
            }
            let snapshot = FileManager.default.fileExists(atPath: location.snapshotURL.path)
            lines.append("Migration safety copy (Recovery): \(snapshot ? "there" : "not there")")
            let last = state.withLock { ($0.last, $0.killNeverReached) }
            if let open = last.0 {
                lines.append("Last launch opened the store in \(format(open.seconds)) s.")
                if let from = open.migratedFrom {
                    lines.append("Last launch migrated version \(from) to \(current).")
                } else {
                    lines.append("Last launch ran no migration.")
                }
                if let step = open.resumedAfter {
                    lines.append(
                        "Last launch found an unfinished migration (journal said \(step)); safety copy put back: \(open.snapshotRestored ? "yes" : "no")."
                    )
                }
                if let problem = open.problem { lines.append("Last launch ended with the problem: \(problem).") }
                for step in open.steps { lines.append("  \(step.name) at +\(format(step.seconds)) s") }
            }
            if let kill = last.1 { lines.append("-migration-kill-at \(kill) was never reached: no migration ran.") }
            return lines
        }

        private static func format(_ seconds: Double) -> String {
            String(format: "%.2f", seconds)
        }
    }

    extension StoreSQLite {
        /// Every row of a closed store file with the date it was saved, for `-make-old-store`.
        static func rowsWithDates(
            of url: URL
        ) throws -> [(kind: String, key: String, payloadVersion: Int, payload: Data, savedAt: Date)] {
            var rows: [(kind: String, key: String, payloadVersion: Int, payload: Data, savedAt: Date)] = []
            try query(url, "SELECT ZKIND, ZKEY, ZPAYLOADVERSION, ZPAYLOAD, ZSAVEDAT FROM ZSTOREDRECORD") { statement in
                guard let kind = sqlite3_column_text(statement, 0), let key = sqlite3_column_text(statement, 1) else {
                    return
                }
                let count = Int(sqlite3_column_bytes(statement, 3))
                let payload = sqlite3_column_blob(statement, 3).map { Data(bytes: $0, count: count) } ?? Data()
                rows.append(
                    (
                        String(cString: kind), String(cString: key), Int(sqlite3_column_int64(statement, 2)), payload,
                        Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 4))
                    ))
            }
            return rows
        }
    }
#endif
