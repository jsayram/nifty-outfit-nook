#if DEBUG
    import Foundation

    /// Sample MetricKit reports for the debug diagnostics screen, shaped like Apple's
    /// `jsonRepresentation()` output. Phase 31 could not be checked against a report from a real
    /// device (the simulator delivers none unless Xcode's Debug, Simulate MetricKit Payloads is
    /// used), so these stand in. They carry text on purpose that must never be kept: a call stack
    /// with library names, a region, a process ID, a bundle ID and an exception's words.
    public enum DiagnosticsSampleReports {
        /// Day-old reports ending `daysAgo` days before now.
        public static func diagnostics(daysAgo: Int = 1, now: Date = .now) -> Data {
            let end = stamp(now.addingTimeInterval(-Double(daysAgo) * 86_400))
            let begin = stamp(now.addingTimeInterval(-Double(daysAgo + 1) * 86_400))
            let meta = """
                "appBuildVersion": "14", "appVersion": "0.1", "deviceType": "iPhone13,2",
                "osVersion": "iPhone OS 26.5 (23F77)", "platformArchitecture": "arm64e", "regionFormat": "US",
                "bundleIdentifier": "com.jsayram.niftyoutfitnook", "pid": 4242, "isTestFlightApp": true,
                "lowPowerModeEnabled": false
                """
            let stack = """
                "callStackTree": {"callStackPerThread": true, "callStacks": [{"threadAttributed": true,
                "callStackRootFrames": [{"binaryUUID": "0F0C6B9E-1111-2222-3333-444455556666", "offsetIntoBinaryTextSegment": 4812,
                "sampleCount": 1, "binaryName": "Maria's Wardrobe", "address": 4300123456}]}]}
                """
            let json = """
                {"timeStampBegin": "\(begin)", "timeStampEnd": "\(end)",
                 "crashDiagnostics": [{"version": "1.0.0", \(stack), "diagnosticMetaData": {\(meta), "exceptionType": 1,
                   "exceptionCode": 1, "signal": 11, "terminationReason": "Namespace SIGNAL, Code 11 Segmentation fault: 11",
                   "virtualMemoryRegionInfo": "0 is not in any region. /Users/maria/closet.sqlite"}}],
                 "hangDiagnostics": [{"version": "1.0.0", \(stack), "diagnosticMetaData": {\(meta), "hangDuration": "2.4 sec"}}],
                 "cpuExceptionDiagnostics": [{"version": "1.0.0", \(stack), "diagnosticMetaData": {\(meta),
                   "totalCPUTime": "91 sec", "totalSampledTime": "180 sec"}}]}
                """
            return Data(json.utf8)
        }

        public static func metrics(daysAgo: Int = 1, now: Date = .now) -> Data {
            let end = stamp(now.addingTimeInterval(-Double(daysAgo) * 86_400))
            let begin = stamp(now.addingTimeInterval(-Double(daysAgo + 1) * 86_400))
            let json = """
                {"timeStampBegin": "\(begin)", "timeStampEnd": "\(end)", "latestApplicationVersion": "0.1",
                 "includesMultipleApplicationVersions": false,
                 "metaData": {"appBuildVersion": "14", "osVersion": "iPhone OS 26.5 (23F77)", "deviceType": "iPhone13,2",
                   "regionFormat": "US", "pid": 4242},
                 "applicationLaunchMetrics": {"histogrammedTimeToFirstDrawKey": {"histogramNumBuckets": 3, "histogramValue": {
                   "0": {"bucketStart": "0 ms", "bucketEnd": "400 ms", "bucketCount": 2},
                   "1": {"bucketStart": "400 ms", "bucketEnd": "800 ms", "bucketCount": 5},
                   "2": {"bucketStart": "800 ms", "bucketEnd": "1200 ms", "bucketCount": 1}}}},
                 "memoryMetrics": {"peakMemoryUsage": "310000 kB", "averageSuspendedMemory":
                   {"averageValue": "90000 kB", "standardDeviation": 1200, "sampleCount": 3}},
                 "applicationExitMetrics": {
                   "foregroundExitData": {"cumulativeNormalAppExitCount": 4, "cumulativeMemoryResourceLimitExitCount": 1,
                     "cumulativeAppWatchdogExitCount": 0, "cumulativeAbnormalExitCount": 0},
                   "backgroundExitData": {"cumulativeNormalAppExitCount": 9, "cumulativeMemoryPressureExitCount": 0,
                     "cumulativeAppWatchdogExitCount": 0, "cumulativeAbnormalExitCount": 0}}}
                """
            return Data(json.utf8)
        }

        private static func stamp(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            return formatter.string(from: date)
        }
    }
#endif
