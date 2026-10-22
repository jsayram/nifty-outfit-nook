import Foundation

/// Sample MetricKit reports for the Phase 31 tests, shaped like `MXDiagnosticPayload` and
/// `MXMetricPayload` `jsonRepresentation()`. None came from a real device (the simulator delivers
/// none). Every one carries text that must never be kept or shared: library names, addresses, a
/// region, a process ID, a bundle ID, a file path and an exception's words.
public enum DiagnosticsSamples {
    // Things that must never be kept. Every sample report carries them.
    public static let planted = [
        "Maria's Wardrobe", "4300123456", "0F0C6B9E", "US", "4242", "com.jsayram.niftyoutfitnook", "closet.sqlite",
        "Segmentation fault", "Namespace SIGNAL", "Dear diary", "arm64e", "/Users/maria",
    ]

    public static let stack = """
        "callStackTree": {"callStackPerThread": true, "callStacks": [{"threadAttributed": true,
        "callStackRootFrames": [{"binaryUUID": "0F0C6B9E-1111-2222-3333-444455556666", "offsetIntoBinaryTextSegment": 4812,
        "sampleCount": 1, "binaryName": "Maria's Wardrobe", "address": 4300123456}]}]}
        """

    public static let meta = """
        "appBuildVersion": "14", "appVersion": "0.1", "deviceType": "iPhone13,2", "osVersion": "iPhone OS 26.5 (23F77)",
        "platformArchitecture": "arm64e", "regionFormat": "US", "bundleIdentifier": "com.jsayram.niftyoutfitnook",
        "pid": 4242, "isTestFlightApp": true, "lowPowerModeEnabled": false
        """

    public static let diagnosticReport = Data(
        """
        {"timeStampBegin": "2026-10-20 00:00:00 +0000", "timeStampEnd": "2026-10-21 00:00:00 +0000",
         "crashDiagnostics": [
           {"version": "1.0.0", \(stack), "diagnosticMetaData": {\(meta), "exceptionType": 1, "exceptionCode": 1, "signal": 11,
            "terminationReason": "Namespace SIGNAL, Code 11 Segmentation fault: 11",
            "virtualMemoryRegionInfo": "0 is not in any region. /Users/maria/closet.sqlite"}},
           {"version": "1.0.0", \(stack), "diagnosticMetaData": {\(meta), "exceptionType": 6, "signal": 5,
            "objectiveCexceptionReason": {"composedMessage": "Dear diary, the hamper"}}}],
         "hangDiagnostics": [{"version": "1.0.0", \(stack), "diagnosticMetaData": {\(meta), "hangDuration": "2.4 sec"}}],
         "cpuExceptionDiagnostics": [{"version": "1.0.0", \(stack), "diagnosticMetaData": {\(meta),
            "totalCPUTime": "91 sec", "totalSampledTime": "180 sec"}}],
         "diskWriteExceptionDiagnostics": [{"version": "1.0.0", \(stack), "diagnosticMetaData": {\(meta),
            "writesCaused": "1500000 kB"}}],
         "appLaunchDiagnostics": [{"version": "1.0.0", \(stack), "diagnosticMetaData": {\(meta), "launchDuration": "6500 ms"}}]}
        """.utf8)

    public static let metricReport = Data(
        """
        {"timeStampBegin": "2026-10-20 00:00:00 +0000", "timeStampEnd": "2026-10-21 00:00:00 +0000",
         "latestApplicationVersion": "0.1", "includesMultipleApplicationVersions": false,
         "metaData": {"appBuildVersion": "14", "osVersion": "iPhone OS 26.5 (23F77)", "deviceType": "iPhone13,2",
           "regionFormat": "US", "pid": 4242, "platformArchitecture": "arm64e"},
         "applicationLaunchMetrics": {
           "histogrammedTimeToFirstDrawKey": {"histogramNumBuckets": 3, "histogramValue": {
             "0": {"bucketStart": "0 ms", "bucketEnd": "400 ms", "bucketCount": 2},
             "1": {"bucketStart": "400 ms", "bucketEnd": "800 ms", "bucketCount": 5},
             "2": {"bucketStart": "800 ms", "bucketEnd": "1200 ms", "bucketCount": 1}}},
           "histogrammedResumeTime": {"histogramNumBuckets": 1, "histogramValue": {
             "0": {"bucketStart": "0 sec", "bucketEnd": "0.2 sec", "bucketCount": 4}}}},
         "memoryMetrics": {"peakMemoryUsage": "310000 kB",
           "averageSuspendedMemory": {"averageValue": "90000 kB", "standardDeviation": 1200, "sampleCount": 3}},
         "applicationExitMetrics": {
           "foregroundExitData": {"cumulativeNormalAppExitCount": 4, "cumulativeMemoryResourceLimitExitCount": 1,
             "cumulativeAppWatchdogExitCount": 2, "cumulativeAbnormalExitCount": 1, "cumulativeBadAccessExitCount": 0},
           "backgroundExitData": {"cumulativeNormalAppExitCount": 9, "cumulativeMemoryResourceLimitExitCount": 0,
             "cumulativeMemoryPressureExitCount": 3, "cumulativeAppWatchdogExitCount": 1, "cumulativeAbnormalExitCount": 2}}}
        """.utf8)
}
