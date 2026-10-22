import Foundation

// What the phone keeps from Apple's MetricKit reports (Phase 31). Two small record types of fixed
// fields: no call stacks, no library or file names, no addresses, no region, no process ID, no
// exception text. Versions are checked against a pattern before they are kept, so a field that
// didn't look like one is dropped, not stored. `DiagnosticsSummary` adds these up for sharing.

/// One diagnostic event from MetricKit: a crash, a hang, a CPU or disk-write exception, or a slow launch.
public struct DiagnosticRecord: Hashable, Sendable, Codable, Identifiable {
    public enum Kind: String, CaseIterable, Hashable, Sendable, Codable {
        case crash
        case hang
        case cpuException
        case diskWriteException
        case slowLaunch
    }

    /// Made from the event's kind, the report's end time and its place in the report, so the same
    /// report read twice is kept once.
    public var id: String
    public var kind: Kind
    /// When the report period ended (MetricKit gives no time for single events).
    public var at: Date
    public var appVersion: String?
    public var build: String?
    public var systemVersion: String?
    public var deviceModel: String?
    /// Crashes only.
    public var exception: CrashExceptionKind?
    public var signal: CrashSignalKind?
    /// Hangs and slow launches: how long, in milliseconds.
    public var durationMs: Int?

    public init(
        id: String, kind: Kind, at: Date, appVersion: String? = nil, build: String? = nil,
        systemVersion: String? = nil, deviceModel: String? = nil, exception: CrashExceptionKind? = nil,
        signal: CrashSignalKind? = nil, durationMs: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.at = at
        self.appVersion = appVersion
        self.build = build
        self.systemVersion = systemVersion
        self.deviceModel = deviceModel
        self.exception = exception
        self.signal = signal
        self.durationMs = durationMs
    }
}

/// One day's speed and memory report from MetricKit, cut down to a few numbers.
public struct MetricSample: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var begin: Date
    public var end: Date
    public var appVersion: String?
    public var build: String?
    public var systemVersion: String?
    public var deviceModel: String?
    /// The typical time from tapping the icon to the first screen, in milliseconds.
    public var launchMedianMs: Int?
    /// The typical time to come back from the background, in milliseconds.
    public var resumeMedianMs: Int?
    public var peakMemoryMB: Int?
    /// Times the system ended the app for using too much memory, in the foreground or the background.
    public var memoryExits: Int
    /// Times the system ended the app for taking too long.
    public var watchdogExits: Int
    /// Other abnormal exits.
    public var abnormalExits: Int

    public init(
        id: String, begin: Date, end: Date, appVersion: String? = nil, build: String? = nil,
        systemVersion: String? = nil, deviceModel: String? = nil, launchMedianMs: Int? = nil,
        resumeMedianMs: Int? = nil, peakMemoryMB: Int? = nil, memoryExits: Int = 0, watchdogExits: Int = 0,
        abnormalExits: Int = 0
    ) {
        self.id = id
        self.begin = begin
        self.end = end
        self.appVersion = appVersion
        self.build = build
        self.systemVersion = systemVersion
        self.deviceModel = deviceModel
        self.launchMedianMs = launchMedianMs
        self.resumeMedianMs = resumeMedianMs
        self.peakMemoryMB = peakMemoryMB
        self.memoryExits = memoryExits
        self.watchdogExits = watchdogExits
        self.abnormalExits = abnormalExits
    }
}

/// Everything the phone has kept, for the debug screen and for building the summary.
public struct DiagnosticsSnapshot: Hashable, Sendable, Codable {
    /// When the phone started keeping reports (or last cleared them).
    public var since: Date
    public var records: [DiagnosticRecord]
    public var samples: [MetricSample]

    public init(since: Date, records: [DiagnosticRecord] = [], samples: [MetricSample] = []) {
        self.since = since
        self.records = records
        self.samples = samples
    }

    /// How long reports are kept, and how many of each.
    public static let keepDays = 30
    public static let maximumRecords = 200
    public static let maximumSamples = 60

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private static func windowStart(now: Date) -> Date {
        calendar.date(byAdding: .day, value: -keepDays, to: now) ?? .distantPast
    }

    /// Adds up the last 30 days into the summary she can share, or `nil` when there's nothing to say.
    public func summary(now: Date) -> DeviceHealthSummary? {
        let start = Self.windowStart(now: now)
        let records = records.filter { $0.at >= start && $0.at <= now.addingTimeInterval(86_400) }
        let samples = samples.filter { $0.end >= start && $0.end <= now.addingTimeInterval(86_400) }

        var counts: [String: DeviceHealthSummary.CrashKind] = [:]
        for record in records where record.kind == .crash {
            let kind = DeviceHealthSummary.CrashKind(
                exception: record.exception ?? .other, signal: record.signal ?? .none, count: 0)
            let key = kind.exception.rawValue + "/" + kind.signal.rawValue
            counts[key, default: kind].count += 1
        }
        let kinds = counts.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.exception != $1.exception { return $0.exception.rawValue < $1.exception.rawValue }
            return $0.signal.rawValue < $1.signal.rawValue
        }

        let launches = samples.compactMap(\.launchMedianMs).sorted()
        let covered = Self.calendar.dateComponents([.day], from: max(since, start), to: now).day ?? 0
        let summary = DeviceHealthSummary(
            windowDays: min(max(covered + 1, 1), Self.keepDays),
            crashes: records.filter { $0.kind == .crash }.count,
            hangs: records.filter { $0.kind == .hang }.count,
            cpuExceptions: records.filter { $0.kind == .cpuException }.count,
            diskWriteExceptions: records.filter { $0.kind == .diskWriteException }.count,
            memoryExits: samples.reduce(0) { $0 + $1.memoryExits },
            watchdogExits: samples.reduce(0) { $0 + $1.watchdogExits },
            longestHangMs: records.filter { $0.kind == .hang }.compactMap(\.durationMs).max(),
            launchMedianMs: launches.isEmpty ? nil : launches[launches.count / 2],
            peakMemoryMB: samples.compactMap(\.peakMemoryMB).max(),
            crashKinds: Array(kinds.prefix(DeviceHealthSummary.maximumCrashKinds))
        ).clamped()
        return summary.isEmpty ? nil : summary
    }

    /// Keeps only what's recent and within the limits, newest first.
    public func pruned(now: Date) -> DiagnosticsSnapshot {
        let start = Self.windowStart(now: now)
        return DiagnosticsSnapshot(
            since: since,
            records: Array(records.filter { $0.at >= start }.sorted { $0.at > $1.at }.prefix(Self.maximumRecords)),
            samples: Array(samples.filter { $0.end >= start }.sorted { $0.end > $1.end }.prefix(Self.maximumSamples)))
    }
}

/// Where the phone keeps its MetricKit reports. `DiagnosticsLog` in Services keeps them in a file.
public protocol DiagnosticsReading: ErasableStore {
    func snapshot() async -> DiagnosticsSnapshot
    /// The summary she can share, or `nil` when there's nothing to say.
    func summary() async -> DeviceHealthSummary?
    /// Stores reports MetricKit delivered, as the raw JSON it gave. Used by the debug screen to add
    /// sample reports; the real collector calls the log directly.
    func ingest(diagnosticPayloads: [Data], metricPayloads: [Data]) async
}

/// No reports are kept: previews, tests and any build that doesn't collect them.
public struct UnavailableDiagnostics: DiagnosticsReading {
    public init() {}
    public func snapshot() async -> DiagnosticsSnapshot { DiagnosticsSnapshot(since: Date()) }
    public func summary() async -> DeviceHealthSummary? { nil }
    public func ingest(diagnosticPayloads: [Data], metricPayloads: [Data]) async {}
    public func eraseAll() async throws(StoreError) {}
}
