#if DEBUG
    import Foundation
    import Models
    import UIKit

    extension DeviceChecksSource {
        /// The Device checks screen's source for the app's own folders.
        public static func make(
            location: BackupLocation = .app, diagnostics: URL = DiagnosticsLog.defaultDirectory
        ) -> DeviceChecksSource {
            DeviceChecksSource(
                begin: { LockProbe.shared.start(storeURL: location.store.storeURL) },
                deviceLines: { deviceLines() },
                fileRows: { DeviceFileChecks.system.rows(location: location, diagnostics: diagnostics) },
                storeLines: { MigrationDebug.storeLines(location: location.store) },
                lockLines: { LockProbe.shared.lines })
        }

        /// Model, iOS and build, with nothing about her.
        static func deviceLines() -> [String] {
            var system = utsname()
            uname(&system)
            let bytes = withUnsafeBytes(of: system.machine) { Array($0) }
            let machine = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            #if targetEnvironment(simulator)
                let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
                let simulator = true
            #else
                let model = machine
                let simulator = false
            #endif
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "?"
            let build = info?["CFBundleVersion"] as? String ?? "?"
            var lines = [
                "Device: \(model), iOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                "App: \(version) (\(build)), Debug",
                "Taken: \(Date.now.formatted(.iso8601))",
            ]
            if simulator {
                lines.append("SIMULATOR: it keeps no Data Protection classes, so ignore the file results.")
            }
            return lines
        }
    }
#endif
