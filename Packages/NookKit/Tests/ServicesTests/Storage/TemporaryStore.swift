import Foundation
import NookTestSupport
import SwiftData

@testable import Services

/// A store folder of its own for one test, under the temporary directory, removed when the test
/// lets go of it. "A relaunch" is a second `NookStorage` opened on the same folder after the
/// first is gone, which is what the app does at launch.
final class TemporaryStore: Sendable {
    let location: StoreLocation

    init(_ label: String = "store") throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "NookStoreTests", directoryHint: .isDirectory)
            .appending(path: "\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        location = StoreLocation(directory: directory)
    }

    deinit {
        location.removeAll()
    }

    /// Opens the store as the app does at launch.
    func open() throws -> NookStorage {
        switch NookStorage.open(at: location, calendar: TestTime.calendar) {
        case .ready(let storage): return storage
        case .problem(let problem): throw OpenFailure(problem: problem)
        }
    }

    struct OpenFailure: Error {
        let problem: StoreProblem
    }
}
