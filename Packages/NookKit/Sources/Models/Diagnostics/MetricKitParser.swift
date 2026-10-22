import Foundation

// Reading MetricKit's JSON (Phase 31).
//
// `MXMetricPayload.jsonRepresentation()` and `MXDiagnosticPayload.jsonRepresentation()` give JSON
// with Apple's own key names; the shapes below are the ones Apple's reports use, and the parser
// reads them loosely on purpose: an unknown key is ignored, a missing or odd value is skipped,
// and a document that isn't JSON gives nothing. It never throws and never keeps what it doesn't
// need. Values with units ("2.5 sec", "150000 kB") are read by their unit. What it keeps is
// whatever `DiagnosticRecord` and `MetricSample` can hold, and nothing else, so a call stack, a
// binary name, a region, a process ID or an exception's text is dropped here, before storage.
public enum MetricKitParser {
    // MARK: Diagnostics

    /// The events in one diagnostic payload.
    public static func diagnostics(from json: Data, receivedAt: Date) -> [DiagnosticRecord] {
        guard let root = object(json) else { return [] }
        let end = date(root["timeStampEnd"]) ?? receivedAt
        let stamp = Int(end.timeIntervalSince1970)
        let groups: [(String, DiagnosticRecord.Kind)] = [
            ("crashDiagnostics", .crash), ("hangDiagnostics", .hang), ("cpuExceptionDiagnostics", .cpuException),
            ("diskWriteExceptionDiagnostics", .diskWriteException), ("appLaunchDiagnostics", .slowLaunch),
        ]
        var records: [DiagnosticRecord] = []
        for (key, kind) in groups {
            guard let events = root[key] as? [Any] else { continue }
            for (index, raw) in events.enumerated() {
                guard let event = raw as? [String: Any] else { continue }
                let meta = event["diagnosticMetaData"] as? [String: Any] ?? [:]
                var record = DiagnosticRecord(
                    id: "\(kind.rawValue)-\(stamp)-\(index)", kind: kind, at: end,
                    appVersion: version(meta["appVersion"]), build: build(meta["appBuildVersion"]),
                    systemVersion: systemVersion(meta["osVersion"]), deviceModel: deviceModel(meta["deviceType"]))
                switch kind {
                case .crash:
                    record.exception = CrashExceptionKind(machType: integer(meta["exceptionType"]))
                    record.signal = CrashSignalKind(number: integer(meta["signal"]))
                case .hang:
                    record.durationMs = milliseconds(meta["hangDuration"])
                case .slowLaunch:
                    record.durationMs = milliseconds(meta["launchDuration"])
                case .cpuException, .diskWriteException:
                    break
                }
                records.append(record)
            }
        }
        return records
    }

    // MARK: Metrics

    /// The numbers in one metric payload, or `nil` if it isn't one.
    public static func metrics(from json: Data, receivedAt: Date) -> MetricSample? {
        guard let root = object(json) else { return nil }
        let end = date(root["timeStampEnd"]) ?? receivedAt
        let begin = date(root["timeStampBegin"]) ?? end.addingTimeInterval(-86_400)
        let meta = root["metaData"] as? [String: Any] ?? [:]
        let launch = root["applicationLaunchMetrics"] as? [String: Any] ?? [:]
        let memory = root["memoryMetrics"] as? [String: Any] ?? [:]
        let exits = root["applicationExitMetrics"] as? [String: Any] ?? [:]
        let foreground = exits["foregroundExitData"] as? [String: Any] ?? [:]
        let background = exits["backgroundExitData"] as? [String: Any] ?? [:]
        func total(_ keys: [String], in groups: [[String: Any]]) -> Int {
            groups.reduce(0) { sum, group in sum + keys.reduce(0) { $0 + (integer(group[$1]) ?? 0) } }
        }
        let groups = [foreground, background]
        let sample = MetricSample(
            id: "metrics-\(Int(end.timeIntervalSince1970))", begin: begin, end: end,
            appVersion: version(root["latestApplicationVersion"]), build: build(meta["appBuildVersion"]),
            systemVersion: systemVersion(meta["osVersion"]), deviceModel: deviceModel(meta["deviceType"]),
            launchMedianMs: histogramMedianMs(launch["histogrammedTimeToFirstDrawKey"]),
            resumeMedianMs: histogramMedianMs(launch["histogrammedResumeTime"]),
            peakMemoryMB: megabytes(memory["peakMemoryUsage"]),
            memoryExits: total(
                ["cumulativeMemoryResourceLimitExitCount", "cumulativeMemoryPressureExitCount"], in: groups),
            watchdogExits: total(["cumulativeAppWatchdogExitCount"], in: groups),
            abnormalExits: total(["cumulativeAbnormalExitCount"], in: groups))
        // A document with none of the parts a metric payload has isn't one.
        let known = ["applicationLaunchMetrics", "memoryMetrics", "applicationExitMetrics", "metaData"]
        return known.contains(where: { root[$0] != nil }) ? sample : nil
    }

    // MARK: Values

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            // A boolean is not a count.
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? nil : number.intValue
        case let text as String:
            return quantity(text).map { Int($0.value.rounded()) }
        default:
            return nil
        }
    }

    /// "2.5 sec" is 2.5 and "sec". A bare number has no unit.
    static func quantity(_ value: Any?) -> (value: Double, unit: String)? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return (number.doubleValue, "")
        }
        guard let text = value as? String else { return nil }
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, let number = Double(first), number.isFinite else { return nil }
        return (number, parts.count > 1 ? parts[1].lowercased().trimmingCharacters(in: .whitespaces) : "")
    }

    /// Milliseconds from a duration with a unit. A bare number is taken as milliseconds.
    static func milliseconds(_ value: Any?) -> Int? {
        guard let (number, unit) = quantity(value) else { return nil }
        let scale: Double
        switch unit {
        case "", "ms", "msec", "msecs", "millisecond", "milliseconds": scale = 1
        case "s", "sec", "secs", "second", "seconds": scale = 1000
        case "min", "mins", "minute", "minutes": scale = 60_000
        case "us", "µs", "μs": scale = 0.001
        case "ns": scale = 0.000_001
        default: return nil
        }
        let result = number * scale
        return result >= 0 && result < 1e9 ? Int(result.rounded()) : nil
    }

    /// Megabytes from a size with a unit. MetricKit's "kB" is 1,000 bytes. A bare number is bytes.
    static func megabytes(_ value: Any?) -> Int? {
        guard let (number, unit) = quantity(value) else { return nil }
        let bytes: Double
        switch unit {
        case "", "b", "byte", "bytes": bytes = number
        case "kb": bytes = number * 1_000
        case "mb": bytes = number * 1_000_000
        case "gb": bytes = number * 1_000_000_000
        case "kib": bytes = number * 1_024
        case "mib": bytes = number * 1_048_576
        case "gib": bytes = number * 1_073_741_824
        default: return nil
        }
        let result = bytes / 1_000_000
        return result >= 0 && result < 1e6 ? Int(result.rounded()) : nil
    }

    /// The middle of the bucket that holds the median, from MetricKit's histogram:
    /// `{"histogramValue": {"0": {"bucketStart": "0 ms", "bucketEnd": "100 ms", "bucketCount": 3}, ...}}`.
    static func histogramMedianMs(_ value: Any?) -> Int? {
        guard let histogram = value as? [String: Any], let buckets = histogram["histogramValue"] as? [String: Any]
        else { return nil }
        let rows: [(start: Int, end: Int, count: Int)] = buckets.values.compactMap { raw in
            guard let bucket = raw as? [String: Any], let start = milliseconds(bucket["bucketStart"]),
                let end = milliseconds(bucket["bucketEnd"]), let count = integer(bucket["bucketCount"]), count > 0
            else { return nil }
            return (start, end, count)
        }.sorted { $0.start < $1.start }
        let total = rows.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        var seen = 0
        for row in rows {
            seen += row.count
            if seen * 2 >= total { return (row.start + row.end) / 2 }
        }
        return nil
    }

    /// MetricKit writes "2026-10-20 00:00:00 +0000".
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        if let date = formatter.date(from: text) { return date }
        return try? Date(text, strategy: .iso8601)
    }

    // MARK: Fields kept only if they look right

    static func version(_ value: Any?) -> String? {
        keep(value, matching: /[0-9A-Za-z.+-]{1,32}/)
    }

    static func build(_ value: Any?) -> String? {
        keep(value, matching: /[0-9A-Za-z.-]{1,16}/)
    }

    static func deviceModel(_ value: Any?) -> String? {
        keep(value, matching: /[A-Za-z0-9,]{1,32}/)
    }

    /// "iPhone OS 26.5 (23F77)" is kept as "26.5". Anything with no version number is dropped.
    static func systemVersion(_ value: Any?) -> String? {
        guard let text = value as? String, text.count <= 80,
            let match = text.firstMatch(of: /[0-9]{1,3}(\.[0-9]{1,3}){0,2}/)
        else { return nil }
        return String(match.0)
    }

    private static func keep(_ value: Any?, matching pattern: Regex<Substring>) -> String? {
        guard let text = value as? String, text.wholeMatch(of: pattern) != nil else { return nil }
        return text
    }
}
