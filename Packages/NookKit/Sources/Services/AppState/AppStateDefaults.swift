import Foundation
import Models

// App state kept across launches in Stage A (Phase 17).
//
// Stage A has no real storage: the closet, looks, profile and everything she types live in
// memory and are gone when the app closes. A few flags would make a test build feel broken if
// they were lost too: that she has finished onboarding, which closet she started with, which
// quick tours she has seen and the "Show tips on new screens" switch. `closet/DATA_MAP.md` puts
// those in the lowest tier (no name, nothing she typed, nothing about her body or closet, no
// dates and no identifier), so they're kept here, in a `UserDefaults` suite only this app can
// read.
//
// The Stage A audit (16 October 2026) added the first name on her sign and the Style Me settings
// on Profile (Preferences, Avoid repeating outfits for, Track laundry): Jose decided a relaunch
// shouldn't undo them. They're Personal, so they're named in `closet/DATA_MAP.md` on their own
// rows. Everything else stays out: her fit, measurements, fitting pieces and try-on photo
// (Sensitive), the remembered source and occasion, and how or when each tour ended are in memory
// only. Phase 21a moves all of this into the real stores.
//
// The suite is a file in the app's own container (Library/Preferences), included in her device
// backup like any app setting. Nothing here is logged or sent.

/// The `UserDefaults` suite and keys for the app state.
public enum AppStateDefaults {
    /// The app's own suite. It isn't an App Group, so no other app or extension can read it.
    public static let suiteName = "com.jsayram.niftyoutfitnook.appstate"

    enum Key {
        static let onboardingCompleted = "onboarding.completed"
        static let startingCloset = "onboarding.startingCloset"
        static let showsTips = "tours.showsTips"
        static let seenVersions = "tours.seenVersions"
        // The name on the sign and the Style Me settings (Stage A audit decisions).
        static let signName = "profile.signName"
        static let pieceMode = "profile.pieceMode"
        static let repeatWindow = "profile.repeatWindow"
        static let tracksLaundry = "profile.tracksLaundry"

        static let profileSettings = [signName, pieceMode, repeatWindow, tracksLaundry]
    }

    /// The tour versions accepted when reading. Anything else in the file is ignored.
    static let versionRange = 1...10_000

    /// The suite with this name. A name can't be a suite only when it's the app's bundle ID or
    /// the global domain, which `suiteName` and the tests' names never are; the app's standard
    /// defaults, also readable by this app alone, stand in if it ever happens.
    static func suite(named name: String) -> UserDefaults {
        UserDefaults(suiteName: name) ?? .standard
    }
}

/// The onboarding state, kept across launches in the app's `UserDefaults` suite.
public actor DefaultsOnboardingStore: OnboardingStateStore {
    private let defaults: UserDefaults

    /// - Parameter suiteName: `AppStateDefaults.suiteName` in the app; a suite of their own in
    ///   tests.
    public init(suiteName: String = AppStateDefaults.suiteName) {
        defaults = AppStateDefaults.suite(named: suiteName)
    }

    /// What's kept. Anything unexpected in the file reads as a fresh install, so the worst a
    /// damaged value can do is show onboarding again.
    public func state() -> OnboardingState {
        guard defaults.object(forKey: AppStateDefaults.Key.onboardingCompleted) as? Bool == true else {
            return .fresh
        }
        let closet = (defaults.object(forKey: AppStateDefaults.Key.startingCloset) as? String)
            .flatMap(StartingCloset.init(rawValue:))
        return OnboardingState(isCompleted: true, startingCloset: closet ?? .sample)
    }

    public func complete(startingCloset closet: StartingCloset) {
        defaults.set(closet.rawValue, forKey: AppStateDefaults.Key.startingCloset)
        defaults.set(true, forKey: AppStateDefaults.Key.onboardingCompleted)
    }

    /// Delete my data, and the debug `-onboarding reset` flag.
    public func eraseAll() {
        defaults.removeObject(forKey: AppStateDefaults.Key.onboardingCompleted)
        defaults.removeObject(forKey: AppStateDefaults.Key.startingCloset)
    }
}

/// Tour progress with the seen versions and the switch kept across launches in the app's
/// `UserDefaults` suite. How each tour ended and when (`TourProgress.records`) is Personal in
/// `closet/DATA_MAP.md`, so it stays in memory for the session.
public actor DefaultsTourProgressStore: TourProgressStore {
    private let defaults: UserDefaults
    /// This session's records.
    private var records: [TourID: TourRecord] = [:]

    /// - Parameter suiteName: as for `DefaultsOnboardingStore`.
    public init(suiteName: String = AppStateDefaults.suiteName) {
        defaults = AppStateDefaults.suite(named: suiteName)
    }

    public func progress() -> TourProgress {
        TourProgress(records: records, seenVersions: seenVersions(), showsTipsOnNewScreens: showsTips())
    }

    public func record(_ record: TourRecord) {
        records[record.tour] = record
        var seen = seenVersions()
        seen[record.tour] = max(seen[record.tour] ?? record.version, record.version)
        write(seen)
    }

    public func setShowsTipsOnNewScreens(_ isOn: Bool) {
        defaults.set(isOn, forKey: AppStateDefaults.Key.showsTips)
    }

    public func forgetSeenTours() {
        records = [:]
        defaults.removeObject(forKey: AppStateDefaults.Key.seenVersions)
    }

    /// Delete my data, and the debug `-tour reset` flag: nothing seen and tips back on.
    public func eraseAll() {
        records = [:]
        defaults.removeObject(forKey: AppStateDefaults.Key.seenVersions)
        defaults.removeObject(forKey: AppStateDefaults.Key.showsTips)
    }

    // MARK: Reading and writing

    /// Tips are on unless she turned them off.
    private func showsTips() -> Bool {
        defaults.object(forKey: AppStateDefaults.Key.showsTips) as? Bool ?? true
    }

    /// The seen versions, keeping only tours the app knows with a sensible version. A value of
    /// the wrong type reads as nothing seen, so a tour shows again rather than never.
    private func seenVersions() -> [TourID: Int] {
        guard let stored = defaults.dictionary(forKey: AppStateDefaults.Key.seenVersions) else { return [:] }
        var seen: [TourID: Int] = [:]
        for tour in TourID.all {
            if let version = stored[tour.rawValue] as? Int, AppStateDefaults.versionRange.contains(version) {
                seen[tour] = version
            }
        }
        return seen
    }

    private func write(_ seen: [TourID: Int]) {
        let stored = Dictionary(uniqueKeysWithValues: seen.map { ($0.key.rawValue, $0.value) })
        defaults.set(stored, forKey: AppStateDefaults.Key.seenVersions)
    }
}

/// The name on her sign and the Style Me settings, kept across launches in the app's
/// `UserDefaults` suite (`KeptSettingsProfileStore` in Models does the rest).
public final class DefaultsProfileSettingsKeeper: ProfileSettingsKeeper {
    // `UserDefaults` is safe to use from any thread (Apple's documentation), which the
    // compiler can't see.
    nonisolated(unsafe) private let defaults: UserDefaults

    /// - Parameter suiteName: as for `DefaultsOnboardingStore`.
    public init(suiteName: String = AppStateDefaults.suiteName) {
        defaults = AppStateDefaults.suite(named: suiteName)
    }

    /// What's kept. A value of the wrong type, or one the app doesn't know, reads as not kept,
    /// so the profile keeps its default for it.
    public func kept() -> KeptProfileSettings {
        typealias Key = AppStateDefaults.Key
        return KeptProfileSettings(
            signName: defaults.object(forKey: Key.signName) as? String,
            pieceMode: (defaults.object(forKey: Key.pieceMode) as? String).flatMap(PieceMode.init(rawValue:)),
            repeatWindow: (defaults.object(forKey: Key.repeatWindow) as? String).flatMap(RepeatWindow.init(rawValue:)),
            tracksLaundry: defaults.object(forKey: Key.tracksLaundry) as? Bool)
    }

    public func keep(_ settings: KeptProfileSettings) {
        typealias Key = AppStateDefaults.Key
        set(settings.signName, for: Key.signName)
        set(settings.pieceMode?.rawValue, for: Key.pieceMode)
        set(settings.repeatWindow?.rawValue, for: Key.repeatWindow)
        set(settings.tracksLaundry, for: Key.tracksLaundry)
    }

    public func forget() {
        for key in AppStateDefaults.Key.profileSettings {
            defaults.removeObject(forKey: key)
        }
    }

    private func set(_ value: (some Any)?, for key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
