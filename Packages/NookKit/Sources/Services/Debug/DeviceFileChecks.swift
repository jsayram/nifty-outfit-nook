#if DEBUG
    import Foundation
    import Models

    /// Reads the Data Protection class and the backup-exclusion flag of every folder and file the
    /// app keeps, for the Device checks screen (debug builds only). What each should be comes from
    /// `closet/SECURITY_STANDARD.md` §3, `DATA_MAP.md` and decisions 0004 (safety copies, staging,
    /// exports, thumbnails) and Phase 31 (diagnostics):
    ///
    /// - everything is `NSFileProtectionComplete`, except the diagnostics file and its folder, which
    ///   are `NSFileProtectionCompleteUntilFirstUserAuthentication` on purpose (MetricKit can
    ///   deliver while the phone is locked);
    /// - the store, its journal and the photos are in device backups; safety copies, staging,
    ///   exports, thumbnails and diagnostics are left out.
    ///
    /// A simulator keeps no protection classes, so a FAIL there means nothing.
    public struct DeviceFileChecks: Sendable {
        let protection: @Sendable (URL) -> String?
        let isExcluded: @Sendable (URL) -> Bool?

        /// Reads the real system.
        public static let system = DeviceFileChecks(
            protection: { url in
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                return (attributes?[.protectionKey] as? FileProtectionType)?.rawValue
            },
            isExcluded: { url in
                (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup
            })

        static let complete = FileProtectionType.complete.rawValue
        static let untilFirstUnlock = FileProtectionType.completeUntilFirstUserAuthentication.rawValue
        /// Files looked at inside one folder, at most. A closet of 2,400 pieces has about 10,000.
        static let fileLimit = 20_000

        /// What to read, in the order the screen lists it.
        private struct Item {
            let label: String
            let url: URL
            let expected: String
            let expectedExcluded: Bool?
            /// Also read every file inside, as one more row.
            var contents = false
        }

        /// Every row for the app's folders.
        public func rows(location: BackupLocation, diagnostics: URL) -> [FileCheckRow] {
            let store = location.store
            let items: [Item] = [
                Item(label: "Store folder", url: store.directory, expected: Self.complete, expectedExcluded: false),
                Item(label: "Nook.store", url: store.storeURL, expected: Self.complete, expectedExcluded: false),
                Item(
                    label: "Nook.store-wal", url: URL(filePath: store.storeURL.path + "-wal"),
                    expected: Self.complete, expectedExcluded: false),
                Item(
                    label: "Nook.store-shm", url: URL(filePath: store.storeURL.path + "-shm"),
                    expected: Self.complete, expectedExcluded: false),
                Item(
                    label: "MigrationJournal.json", url: store.journalURL, expected: Self.complete,
                    expectedExcluded: false),
                Item(
                    label: "Recovery (migration safety copy)", url: store.recoveryDirectory, expected: Self.complete,
                    expectedExcluded: true, contents: true),
                Item(
                    label: "RestoreSafetyCopy", url: location.safetyCopy, expected: Self.complete,
                    expectedExcluded: true, contents: true),
                Item(
                    label: "RestoreJournal.json", url: location.restoreJournal, expected: Self.complete,
                    expectedExcluded: nil),
                Item(
                    label: "Photos", url: location.photos, expected: Self.complete, expectedExcluded: false,
                    contents: true),
                Item(
                    label: "Thumbnails", url: location.thumbnails, expected: Self.complete, expectedExcluded: true,
                    contents: true),
                Item(
                    label: "Restore staging", url: location.staging, expected: Self.complete, expectedExcluded: true,
                    contents: true),
                Item(
                    label: "Exports", url: location.exports, expected: Self.complete, expectedExcluded: true,
                    contents: true),
                Item(
                    label: "Diagnostics folder", url: diagnostics, expected: Self.untilFirstUnlock,
                    expectedExcluded: nil),
                Item(
                    label: "Diagnostics reports.json", url: diagnostics.appending(path: "reports.json"),
                    expected: Self.untilFirstUnlock, expectedExcluded: true),
            ]
            return items.flatMap { item -> [FileCheckRow] in
                let own = row(item)
                return item.contents ? [own, contentsRow(item)] : [own]
            }
        }

        private func row(_ item: Item) -> FileCheckRow {
            guard FileManager.default.fileExists(atPath: item.url.path) else {
                return FileCheckRow(
                    label: item.label, verdict: .notPresent, expected: item.expected, actual: nil,
                    expectedExcluded: item.expectedExcluded, actualExcluded: nil)
            }
            let actual = protection(item.url)
            let excluded = isExcluded(item.url)
            let verdict: FileCheckRow.Verdict
            if actual == nil {
                verdict = .notReported
            } else if actual != item.expected || (item.expectedExcluded.map { $0 != excluded } ?? false) {
                verdict = .fail
            } else {
                verdict = .pass
            }
            return FileCheckRow(
                label: item.label, verdict: verdict, expected: item.expected, actual: actual,
                expectedExcluded: item.expectedExcluded, actualExcluded: excluded)
        }

        /// One row for all the files inside a folder: how many, and the classes found.
        private func contentsRow(_ item: Item) -> FileCheckRow {
            let label = item.label + ": files inside"
            guard FileManager.default.fileExists(atPath: item.url.path) else {
                return FileCheckRow(
                    label: label, verdict: .notPresent, expected: item.expected, actual: nil, expectedExcluded: nil,
                    actualExcluded: nil)
            }
            var counts: [String: Int] = [:]
            var files = 0
            let walker = FileManager.default.enumerator(
                at: item.url, includingPropertiesForKeys: [.isRegularFileKey])
            while let url = walker?.nextObject() as? URL, files < Self.fileLimit {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                files += 1
                counts[protection(url) ?? "no class", default: 0] += 1
            }
            guard files > 0 else {
                return FileCheckRow(
                    label: label, verdict: .notPresent, expected: item.expected, actual: nil, expectedExcluded: nil,
                    actualExcluded: nil, detail: "no files yet")
            }
            let summary = counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
            let capped = files >= Self.fileLimit ? " (first \(Self.fileLimit) only)" : ""
            let verdict: FileCheckRow.Verdict
            if counts[item.expected] == files {
                verdict = .pass
            } else if counts["no class"] == files {
                verdict = .notReported
            } else {
                verdict = .fail
            }
            return FileCheckRow(
                label: label, verdict: verdict, expected: item.expected,
                actual: counts.count == 1 ? counts.keys.first : "mixed",
                expectedExcluded: nil, actualExcluded: nil, detail: "\(files) files: \(summary)\(capped)")
        }
    }
#endif
