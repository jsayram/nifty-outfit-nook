import Foundation

/// A point where the migration can be stopped, for the tests. The coordinator calls `hit` at
/// each step; a test sets a handler that throws there, standing for the app being killed, and
/// then opens the store again as the next launch would. With no handler, which is always the
/// case in the app, `hit` does nothing. (Debug builds also read `-migration-kill-at <name>`, which
/// really kills the app there, for the device checks.)
enum StoreCheckpoint {
    @TaskLocal static var handler: (@Sendable (String) throws -> Void)?

    static func hit(_ name: String) throws {
        try handler?(name)
        #if DEBUG
            // `-migration-kill-at` and `-migration-pause-at` on a device (`MigrationDebug`).
            MigrationDebug.reached(name)
        #endif
    }
}
