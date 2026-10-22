import Foundation
import Models

/// The phone's own crash, hang and speed reports, kept in one small file (Phase 31).
///
/// What goes in is whatever `MetricKitParser` keeps: fixed fields only, no call stacks, library
/// names, addresses, region or process IDs. The file lives in the app's own folder, is left out of
/// device backups (it describes this phone, not her), and holds at most 200 events and 60 daily
/// samples from the last 30 days. Nothing is sent from here: `summary()` only adds the records up,
/// and Send feedback shares that summary only if she turns it on for a note. Delete my data
/// clears the file; so does deleting the app.
///
/// File protection is `completeUntilFirstUserAuthentication`, not `complete`: MetricKit can
/// deliver reports while the phone is locked, and a write that fails then would lose them. The
/// file holds nothing about her or her closet.
public actor DiagnosticsLog: DiagnosticsReading {
    /// The file's folder inside Application Support.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory)
    }

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var state: DiagnosticsSnapshot?

    /// - Parameters:
    ///   - directory: where the file goes; tests pass a temporary folder.
    ///   - now: the clock, so tests can move time.
    public init(directory: URL = DiagnosticsLog.defaultDirectory, now: @escaping @Sendable () -> Date = { Date() }) {
        fileURL = directory.appending(path: "reports.json", directoryHint: .notDirectory)
        self.now = now
    }

    // MARK: DiagnosticsReading

    public func snapshot() -> DiagnosticsSnapshot {
        loaded().pruned(now: now())
    }

    public func summary() -> DeviceHealthSummary? {
        loaded().summary(now: now())
    }

    public func ingest(diagnosticPayloads: [Data], metricPayloads: [Data]) {
        let received = now()
        var next = loaded()
        for payload in diagnosticPayloads {
            for record in MetricKitParser.diagnostics(from: payload, receivedAt: received)
            where !next.records.contains(where: { $0.id == record.id }) {
                next.records.append(record)
            }
        }
        for payload in metricPayloads {
            if let sample = MetricKitParser.metrics(from: payload, receivedAt: received),
                !next.samples.contains(where: { $0.id == sample.id })
            {
                next.samples.append(sample)
            }
        }
        state = next.pruned(now: received)
        save()
    }

    public func eraseAll() throws(StoreError) {
        state = DiagnosticsSnapshot(since: now())
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            throw StoreError.unavailable
        }
    }

    // MARK: The file

    private func loaded() -> DiagnosticsSnapshot {
        if let state { return state }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A missing or damaged file starts a fresh log. Nothing in it is worth stopping for.
        let read = (try? Data(contentsOf: fileURL)).flatMap { try? decoder.decode(DiagnosticsSnapshot.self, from: $0) }
        let snapshot = read ?? DiagnosticsSnapshot(since: now())
        state = snapshot
        return snapshot
    }

    private func save() {
        guard let state else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var excluded = fileURL
            try excluded.setResourceValues(values)
        } catch {
            // The next report tries again; the reports in memory are not lost.
        }
    }
}
