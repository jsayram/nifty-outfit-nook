#if DEBUG
    import Foundation
    import Models
    import Testing

    @testable import Features

    /// The Device checks screen's report (debug builds only): plain text, with the result of every
    /// row, and nothing but class names, counts and times.
    @MainActor
    struct DeviceChecksTests {
        private nonisolated static let rows = [
            FileCheckRow(
                label: "Nook.store", verdict: .pass, expected: "NSFileProtectionComplete",
                actual: "NSFileProtectionComplete", expectedExcluded: false, actualExcluded: false),
            FileCheckRow(
                label: "Thumbnails", verdict: .fail, expected: "NSFileProtectionComplete",
                actual: "NSFileProtectionNone", expectedExcluded: true, actualExcluded: false),
            FileCheckRow(
                label: "Exports", verdict: .notPresent, expected: "NSFileProtectionComplete", actual: nil,
                expectedExcluded: true, actualExcluded: nil),
        ]

        private nonisolated static let source = DeviceChecksSource(
            begin: {}, deviceLines: { ["Device: iPhone14,7, iOS 26.5"] }, fileRows: { rows },
            storeLines: { ["Records: 3"] }, lockLines: { [] })

        @Test func aRowSaysWhatItIsAndWhatItShouldHaveBeen() {
            #expect(DeviceChecksModel.describe(Self.rows[0]) == "NSFileProtectionComplete | backup: included")
            #expect(
                DeviceChecksModel.describe(Self.rows[1])
                    == "NSFileProtectionNone | expected NSFileProtectionComplete | backup: included (expected left out)"
            )
            #expect(DeviceChecksModel.describe(Self.rows[2]) == "nothing there yet")
        }

        @Test func theReportHasEverySectionAsPlainText() async throws {
            let model = DeviceChecksModel(source: Self.source)
            model.refresh()
            for _ in 0..<100 where model.rows.isEmpty {
                try await Task.sleep(for: .milliseconds(20))
            }
            let report = model.report
            #expect(report.hasPrefix("Nifty Outfit Nook device checks\nFAIL: 1 passed, 1 failed, 1 not there yet"))
            #expect(report.contains("PASS | Nook.store | NSFileProtectionComplete | backup: included"))
            #expect(report.contains("FAIL | Thumbnails | "))
            #expect(report.contains("Store and last migration\nRecords: 3"))
            #expect(report.contains("Locked-phone test\nNothing yet."))
            #expect(report.contains("Device: iPhone14,7, iOS 26.5"))
        }
    }
#endif
