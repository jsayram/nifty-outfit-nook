import Foundation

/// A point where the migration can be stopped, for the tests. The coordinator calls `hit` at
/// each step; a test sets a handler that throws there, standing for the app being killed, and
/// then opens the store again as the next launch would. With no handler, which is always the
/// case in the app, `hit` does nothing.
enum StoreCheckpoint {
    @TaskLocal static var handler: (@Sendable (String) throws -> Void)?

    static func hit(_ name: String) throws {
        try handler?(name)
    }
}
