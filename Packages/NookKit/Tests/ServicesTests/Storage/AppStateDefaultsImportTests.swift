import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

@testable import Services

/// Phase 21a moves Stage A's `UserDefaults` suite into the store once, then empties the suite.
/// Each test has a suite and a store of its own.
struct AppStateDefaultsImportTests {
    typealias Key = AppStateDefaults.Key

    /// A suite as a Stage A TestFlight build left it.
    private func stageASuite() -> AppStateDefaultsTests.Suite {
        let suite = AppStateDefaultsTests.Suite()
        suite.set(true, for: Key.onboardingCompleted)
        suite.set("empty", for: Key.startingCloset)
        suite.set(false, for: Key.showsTips)
        suite.set(["home": 2, "closet": 1, "nope": 3], for: Key.seenVersions)
        suite.set("Lily", for: Key.signName)
        suite.set("onlyMine", for: Key.pieceMode)
        suite.set("twoWeeks", for: Key.repeatWindow)
        suite.set(true, for: Key.tracksLaundry)
        return suite
    }

    @Test func movesEverythingInOnceAndEmptiesTheSuite() async throws {
        let suite = stageASuite()
        let store = try TemporaryStore("import")
        let storage = try store.open()
        #expect(AppStateDefaultsImport.run(suiteName: suite.name, into: storage.container) == .imported)

        #expect(try await storage.onboarding.state() == OnboardingState(isCompleted: true, startingCloset: .empty))
        let tours = try await storage.tours.progress()
        #expect(tours.seenVersions == [.home: 2, .closet: 1])
        #expect(!tours.showsTipsOnNewScreens)
        let profile = try await storage.profile.profile()
        #expect(profile.signName == "Lily")
        #expect(profile.preferences == Preferences(pieceMode: .onlyMine, repeatWindow: .twoWeeks, tracksLaundry: true))
        // Nothing else in the profile came from the suite.
        var expected = Profile(signName: "Lily")
        expected.preferences = profile.preferences
        #expect(profile == expected)
        #expect(suite.contents.isEmpty)

        // A relaunch finds it done and changes nothing.
        try await storage.profile.update { $0.signName = "Lil" }
        let relaunched = try store.open()
        #expect(AppStateDefaultsImport.run(suiteName: suite.name, into: relaunched.container) == .alreadyDone)
        #expect(try await relaunched.profile.profile().signName == "Lil")
    }

    /// A fresh install has nothing to move, and still never imports later.
    @Test func aFreshInstallHasNothingToMove() async throws {
        let suite = AppStateDefaultsTests.Suite()
        let store = try TemporaryStore("fresh")
        let storage = try store.open()
        #expect(AppStateDefaultsImport.run(suiteName: suite.name, into: storage.container) == .nothingToImport)
        #expect(try await storage.onboarding.state() == .fresh)
        #expect(try await storage.tours.progress() == .fresh)
        #expect(try await storage.profile.profile() == Profile())

        // Something writing the old suite later isn't taken in, and is cleared.
        suite.set("Someone", for: Key.signName)
        #expect(AppStateDefaultsImport.run(suiteName: suite.name, into: storage.container) == .alreadyDone)
        #expect(try await storage.profile.profile().signName == "")
        #expect(suite.contents.isEmpty)
    }

    /// Killed after writing the values but before noting it: the next launch does it again, with
    /// the same result.
    @Test func runningTwiceAfterAnInterruptionIsTheSame() async throws {
        let suite = stageASuite()
        let store = try TemporaryStore("twice")
        let storage = try store.open()
        AppStateDefaultsImport.run(suiteName: suite.name, into: storage.container)
        let first = try await storage.profile.profile()
        // Stand in for the crash: forget the note, and put the suite back.
        try RecordTable<StoredDefaultsImport>(kind: .defaultsImport).removeAll(in: ModelContext(storage.container))
        let again = stageASuite()
        #expect(AppStateDefaultsImport.run(suiteName: again.name, into: storage.container) == .imported)
        #expect(try await storage.profile.profile() == first)
        #expect(try await storage.tours.progress().seenVersions == [.home: 2, .closet: 1])
    }

    /// Damaged values read as not set, as they did in Stage A, and a bad name is left out.
    @Test func damagedValuesReadSafely() async throws {
        let suite = AppStateDefaultsTests.Suite()
        suite.set("yes", for: Key.onboardingCompleted)
        suite.set(String(repeating: "L", count: NameRules.signNameMaximum + 5), for: Key.signName)
        suite.set("sometimes", for: Key.repeatWindow)
        suite.set(["home": "two"], for: Key.seenVersions)
        let store = try TemporaryStore("damaged")
        let storage = try store.open()
        #expect(AppStateDefaultsImport.run(suiteName: suite.name, into: storage.container) == .imported)
        #expect(try await storage.onboarding.state() == .fresh)
        #expect(try await storage.tours.progress() == .fresh)
        #expect(try await storage.profile.profile() == Profile())
    }

    /// Values already in the store win over the suite's.
    @Test func theStoreWins() async throws {
        let suite = stageASuite()
        let store = try TemporaryStore("wins")
        let storage = try store.open()
        try await storage.profile.save(Profile(signName: "Rose"))
        try await storage.onboarding.complete(startingCloset: .sample)
        AppStateDefaultsImport.run(suiteName: suite.name, into: storage.container)
        #expect(try await storage.profile.profile().signName == "Rose")
        #expect(try await storage.onboarding.state().startingCloset == .sample)
    }
}
