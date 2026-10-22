#if DEBUG
    import Foundation
    import Models
    import Testing

    @testable import Services

    /// The Device checks screen's file protection rows (debug builds only), with a stand-in for the
    /// system so a Mac, which keeps no protection classes, can play both a good and a bad phone.
    struct DeviceFileChecksTests {
        private static let complete = "NSFileProtectionComplete"
        private static let untilFirstUnlock = "NSFileProtectionCompleteUntilFirstUserAuthentication"

        private struct Folders {
            let root: URL
            let location: BackupLocation
            let diagnostics: URL

            init() throws {
                root = FileManager.default.temporaryDirectory.appending(
                    path: "DeviceChecks-\(UUID().uuidString)", directoryHint: .isDirectory)
                location = BackupLocation.inside(root)
                diagnostics = root.appending(path: "Diagnostics", directoryHint: .isDirectory)
            }

            func make(_ files: [URL]) throws {
                for file in files {
                    try FileManager.default.createDirectory(
                        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data("x".utf8).write(to: file)
                }
            }

            func remove() { try? FileManager.default.removeItem(at: root) }
        }

        /// A phone that gives every file `complete` (the diagnostics ones the weaker class) and
        /// leaves out of backups what the design leaves out, with the classes or flags of some files changed.
        private static func goodPhone(
            _ folders: Folders, override: [String: String] = [:], excludedOverride: [String: Bool] = [:]
        ) -> DeviceFileChecks {
            let diagnostics = folders.diagnostics.path
            let left: [String] = [
                folders.location.thumbnails.path, folders.location.staging.path, folders.location.exports.path,
                folders.location.store.recoveryDirectory.path, folders.location.safetyCopy.path,
                folders.diagnostics.appending(path: "reports.json").path,
            ]
            return DeviceFileChecks(
                protection: { url in
                    if let changed = override[url.lastPathComponent] { return changed }
                    return url.path.hasPrefix(diagnostics) ? untilFirstUnlock : complete
                },
                isExcluded: { url in
                    if let changed = excludedOverride[url.lastPathComponent] { return changed }
                    return left.contains(url.path)
                })
        }

        private static func row(_ label: String, in rows: [FileCheckRow]) throws -> FileCheckRow {
            try #require(rows.first { $0.label == label })
        }

        @Test func aPhoneThatKeepsEveryRulePasses() throws {
            let folders = try Folders()
            defer { folders.remove() }
            let location = folders.location
            try folders.make([
                location.store.storeURL, URL(filePath: location.store.storeURL.path + "-wal"),
                URL(filePath: location.store.storeURL.path + "-shm"), location.store.journalURL,
                location.store.snapshotURL, location.photos.appending(path: "a"), location.photos.appending(path: "b"),
                location.thumbnails.appending(path: "t1"), folders.diagnostics.appending(path: "reports.json"),
            ])
            let read = Self.goodPhone(folders).rows(location: location, diagnostics: folders.diagnostics)
            for label in ["Nook.store", "Nook.store-wal", "Nook.store-shm", "MigrationJournal.json", "Photos"] {
                #expect(try Self.row(label, in: read).verdict == .pass, "\(label)")
            }
            let photos = try Self.row("Photos: files inside", in: read)
            #expect(photos.verdict == .pass)
            #expect(photos.detail == "2 files: 2 \(Self.complete)")
            #expect(try Self.row("Diagnostics reports.json", in: read).verdict == .pass)
            #expect(try Self.row("Recovery (migration safety copy)", in: read).verdict == .pass)
            #expect(try Self.row("Exports", in: read).verdict == .notPresent)
            #expect(FileCheckRow.summary(read).hasPrefix("PASS: "))
        }

        @Test func aWeakerClassOnOneFileFails() throws {
            let folders = try Folders()
            defer { folders.remove() }
            let location = folders.location
            try folders.make([
                location.store.storeURL, location.photos.appending(path: "weak"), location.photos.appending(path: "ok"),
            ])
            let phone = Self.goodPhone(folders, override: ["weak": Self.untilFirstUnlock])
            let read = phone.rows(location: location, diagnostics: folders.diagnostics)
            #expect(try Self.row("Nook.store", in: read).verdict == .pass)
            let photos = try Self.row("Photos: files inside", in: read)
            #expect(photos.verdict == .fail)
            #expect(photos.actual == "mixed")
            #expect(photos.detail?.contains("1 \(Self.untilFirstUnlock)") == true)
            #expect(FileCheckRow.summary(read).hasPrefix("FAIL: "))
        }

        @Test func theStoreFileInTheWrongClassFails() throws {
            let folders = try Folders()
            defer { folders.remove() }
            try folders.make([folders.location.store.storeURL])
            let phone = Self.goodPhone(folders, override: ["Nook.store": Self.untilFirstUnlock])
            let read = phone.rows(location: folders.location, diagnostics: folders.diagnostics)
            let store = try Self.row("Nook.store", in: read)
            #expect(store.verdict == .fail)
            #expect(store.expected == Self.complete)
            #expect(store.actual == Self.untilFirstUnlock)
        }

        @Test func diagnosticsExpectTheWeakerClassOnPurpose() throws {
            let folders = try Folders()
            defer { folders.remove() }
            try folders.make([folders.diagnostics.appending(path: "reports.json")])
            let phone = Self.goodPhone(folders, override: ["reports.json": Self.complete])
            let read = phone.rows(location: folders.location, diagnostics: folders.diagnostics)
            #expect(try Self.row("Diagnostics reports.json", in: read).verdict == .fail)
            #expect(try Self.row("Diagnostics folder", in: read).verdict == .pass)
        }

        @Test func aFolderThatShouldBeLeftOutOfBackupsButIsntFails() throws {
            let folders = try Folders()
            defer { folders.remove() }
            try folders.make([
                folders.location.thumbnails.appending(path: "t1"), folders.location.photos.appending(path: "p"),
            ])
            let phone = Self.goodPhone(folders, excludedOverride: ["Thumbnails": false, "Photos": true])
            let read = phone.rows(location: folders.location, diagnostics: folders.diagnostics)
            #expect(try Self.row("Thumbnails", in: read).verdict == .fail)
            // The photos are in device backups on purpose.
            #expect(try Self.row("Photos", in: read).verdict == .fail)
        }

        @Test func aFileWithNoReportedClassIsNotAPass() throws {
            let folders = try Folders()
            defer { folders.remove() }
            try folders.make([folders.location.store.storeURL, folders.location.thumbnails.appending(path: "t1")])
            let phone = DeviceFileChecks(protection: { _ in nil }, isExcluded: { _ in false })
            let read = phone.rows(location: folders.location, diagnostics: folders.diagnostics)
            #expect(try Self.row("Nook.store", in: read).verdict == .notReported)
            #expect(try Self.row("Thumbnails: files inside", in: read).verdict == .notReported)
            #expect(FileCheckRow.summary(read).contains("no class reported"))
        }

        @Test func nothingThereMeansNothingChecked() throws {
            let folders = try Folders()
            let read = Self.goodPhone(folders).rows(location: folders.location, diagnostics: folders.diagnostics)
            #expect(read.allSatisfy { $0.verdict == .notPresent })
            #expect(FileCheckRow.summary(read).hasPrefix("NOTHING CHECKED"))
        }

        @Test func theLockProbeSaysWhetherTheFileCouldBeRead() throws {
            let folders = try Folders()
            defer { folders.remove() }
            let file = folders.location.store.storeURL
            #expect(LockProbe.readResult(storeURL: file).hasPrefix("PASS"))
            try folders.make([file])
            #expect(LockProbe.readResult(storeURL: file).hasPrefix("FAIL"))
        }
    }
#endif
