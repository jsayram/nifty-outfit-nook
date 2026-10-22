#if DEBUG
    import Models
    import Observation
    import SwiftUI
    import UIKit

    /// The Device checks screen, for the iPhone checklist (`closet/DEVICE_TEST_CHECKLIST.md` 2.9,
    /// 2.10 and 2.16): the Data Protection class of the store, its log files, the photos, thumbnails,
    /// safety copies and exports, with a pass or fail against what the design says; what the store
    /// and the last migration did; and whether the store can be read while the phone is locked.
    /// "Copy report" puts it all on the clipboard as plain text: counts, class names and times,
    /// no file names from her closet and nothing she typed.
    ///
    /// Debug builds only: launch with `-device-checks`.
    public struct DeviceChecksScreen: View {
        @State private var model: DeviceChecksModel

        public init(source: DeviceChecksSource) {
            _model = State(initialValue: DeviceChecksModel(source: source))
        }

        public var body: some View {
            NavigationStack {
                List {
                    Section {
                        Text(verbatim: model.overall)
                            .font(.headline)
                            .accessibilityIdentifier("deviceChecks.overall")
                        ForEach(model.deviceLines, id: \.self) { line in
                            Text(verbatim: line).font(.footnote.monospaced())
                        }
                    }
                    Section {
                        Button {
                            model.refresh()
                        } label: {
                            Text(verbatim: "Read again")
                        }
                        .accessibilityIdentifier("deviceChecks.refresh")
                        Button {
                            UIPasteboard.general.string = model.report
                            model.copied = true
                        } label: {
                            Text(verbatim: model.copied ? "Copied" : "Copy report")
                        }
                        .accessibilityIdentifier("deviceChecks.copy")
                    }
                    Section {
                        ForEach(model.rows) { row in
                            FileRowView(row: row)
                        }
                    } header: {
                        Text(verbatim: "File protection")
                    } footer: {
                        Text(
                            verbatim:
                                "Expected: everything NSFileProtectionComplete, except Diagnostics (CompleteUntilFirstUserAuthentication). Left out of backups: safety copies, staging, exports, thumbnails, diagnostics."
                        )
                    }
                    Section {
                        ForEach(model.storeLines, id: \.self) { line in
                            Text(verbatim: line).font(.footnote.monospaced())
                        }
                    } header: {
                        Text(verbatim: "Store and last migration")
                    }
                    Section {
                        ForEach(model.lockLines, id: \.self) { line in
                            Text(verbatim: line).font(.footnote.monospaced())
                        }
                    } header: {
                        Text(verbatim: "Locked-phone test")
                    } footer: {
                        Text(
                            verbatim:
                                "Leave this screen open, lock the phone, wait a minute, unlock, then tap Read again. The check reads Nook.store 15 seconds after the lock; failing to read it is the pass."
                        )
                    }
                }
                .navigationTitle(Text(verbatim: "Device checks"))
                .task {
                    model.begin()
                    model.refresh()
                }
            }
            .accessibilityIdentifier("deviceChecks")
        }
    }

    private struct FileRowView: View {
        let row: FileCheckRow

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: row.label).font(.subheadline)
                    Spacer()
                    Text(verbatim: row.verdict.rawValue)
                        .font(.footnote.bold().monospaced())
                        .foregroundStyle(row.verdict == .fail ? Color.red : Color.primary)
                }
                Text(verbatim: DeviceChecksModel.describe(row)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @MainActor
    @Observable
    final class DeviceChecksModel {
        private(set) var rows: [FileCheckRow] = []
        private(set) var deviceLines: [String] = []
        private(set) var storeLines: [String] = []
        private(set) var lockLines: [String] = []
        private(set) var overall = "Reading..."
        var copied = false
        @ObservationIgnored private let source: DeviceChecksSource
        @ObservationIgnored private var started = false

        init(source: DeviceChecksSource) {
            self.source = source
        }

        func begin() {
            guard !started else { return }
            started = true
            source.begin()
        }

        func refresh() {
            copied = false
            let source = source
            Task {
                let read = await Task.detached {
                    (
                        source.fileRows(), source.deviceLines(), source.storeLines(), source.lockLines()
                    )
                }.value
                rows = read.0
                deviceLines = read.1 + memoryLines()
                storeLines = read.2
                lockLines = read.3.isEmpty ? ["Nothing yet."] : read.3
                overall = FileCheckRow.summary(rows)
            }
        }

        /// Everything on the screen as plain text.
        var report: String {
            var text = ["Nifty Outfit Nook device checks", overall, ""]
            text += deviceLines
            text += ["", "File protection (label | result | class | left out of backups)"]
            text += rows.map { "\($0.verdict.rawValue) | \($0.label) | \(Self.describe($0))" }
            text += ["", "Store and last migration"] + storeLines
            text += ["", "Locked-phone test"] + lockLines
            return text.joined(separator: "\n")
        }

        static func describe(_ row: FileCheckRow) -> String {
            var parts: [String] = []
            if let actual = row.actual { parts.append(actual) }
            if row.verdict == .fail || row.verdict == .notReported { parts.append("expected \(row.expected)") }
            if let excluded = row.actualExcluded {
                let expectation = row.expectedExcluded.map {
                    $0 == excluded ? "" : " (expected \($0 ? "left out" : "included"))"
                }
                parts.append("backup: \(excluded ? "left out" : "included")\(expectation ?? "")")
            }
            if let detail = row.detail { parts.append(detail) }
            return parts.isEmpty ? "nothing there yet" : parts.joined(separator: " | ")
        }

        private func memoryLines() -> [String] {
            let megabytes = { (bytes: UInt64) in String(format: "%.0f", Double(bytes) / 1_048_576) }
            return [
                "Memory now \(megabytes(ProcessMemory.footprint())) MB, peak since launch \(megabytes(ProcessMemory.lifetimePeak())) MB"
            ]
        }
    }
#endif
