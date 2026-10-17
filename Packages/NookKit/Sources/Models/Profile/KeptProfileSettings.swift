import Foundation
import Synchronization

// The name on her sign and the Style Me settings, kept across launches in Stage A (Stage A audit
// decisions, 16 October 2026).
//
// Stage A keeps the profile in memory, so a relaunch put Hello back on the sign and Preferences,
// the repeat setting and Track laundry back to their defaults. Jose decided the test build keeps
// those four values. Nothing else in the profile is kept: her fit, measurements, fitting pieces
// and try-on photo are Sensitive and stay in memory, and so do the remembered source and
// occasion. Phase 21a keeps the whole profile in the real store.

/// The part of the profile kept across launches. A value is `nil` when nothing usable is kept.
///
/// Data tier: **Personal** (the first name on the sign and her standing choices).
public struct KeptProfileSettings: Hashable, Sendable {
    public var signName: String?
    public var pieceMode: PieceMode?
    public var repeatWindow: RepeatWindow?
    public var tracksLaundry: Bool?

    public init(
        signName: String? = nil, pieceMode: PieceMode? = nil, repeatWindow: RepeatWindow? = nil,
        tracksLaundry: Bool? = nil
    ) {
        self.signName = signName
        self.pieceMode = pieceMode
        self.repeatWindow = repeatWindow
        self.tracksLaundry = tracksLaundry
    }

    /// The values to keep from a saved profile.
    public init(_ profile: Profile) {
        self.init(
            signName: profile.signName, pieceMode: profile.preferences.pieceMode,
            repeatWindow: profile.preferences.repeatWindow, tracksLaundry: profile.preferences.tracksLaundry)
    }

    /// Nothing kept: a fresh install, or after Delete my data.
    public static let none = KeptProfileSettings()

    /// Puts what's kept into `profile`. A kept name that breaks the sign's rules is left out, so a
    /// damaged value can't stop the profile from saving.
    public func apply(to profile: inout Profile) {
        if let signName, let checked = try? NameRules.signName(signName) {
            profile.signName = checked
        }
        if let pieceMode {
            profile.preferences.pieceMode = pieceMode
        }
        if let repeatWindow {
            profile.preferences.repeatWindow = repeatWindow
        }
        if let tracksLaundry {
            profile.preferences.tracksLaundry = tracksLaundry
        }
    }
}

/// Where the kept settings live. Reading and writing are quick and local, so they don't wait:
/// the settings are read once while the app's services are built.
public protocol ProfileSettingsKeeper: Sendable {
    /// What's kept, or `.none`.
    func kept() -> KeptProfileSettings
    func keep(_ settings: KeptProfileSettings)
    /// Delete my data, and the debug `-onboarding reset` flag.
    func forget()
}

/// A profile store that keeps the name on the sign and the Style Me settings across launches,
/// in front of a store that keeps the rest (in memory in Stage A).
///
/// It starts from the launch's profile with the kept settings put in, and after every save it
/// keeps them again from what the store saved. Erasing it forgets them too. It passes the same
/// `ProfileStoreContract` as every other profile store.
public actor KeptSettingsProfileStore: ProfileStore {
    private let base: any ProfileStore
    private let keeper: any ProfileSettingsKeeper
    /// Numbers each change in the order the wrapped store makes it. Two changes made at once can
    /// come back here in either order, so only a newer one than the last kept is written.
    private let changes = ChangeCounter()
    private var lastKept = 0

    /// - Parameters:
    ///   - profile: the profile the launch starts from (the sample's, or a fresh one).
    ///   - keeper: where the settings are kept.
    ///   - makeBase: makes the store for everything else, given the profile with the kept
    ///     settings put in.
    public init(
        profile: Profile, keeper: any ProfileSettingsKeeper, base makeBase: (Profile) -> any ProfileStore
    ) {
        var profile = profile
        keeper.kept().apply(to: &profile)
        self.keeper = keeper
        base = makeBase(profile)
    }

    public func profile() async throws(StoreError) -> Profile {
        try await base.profile()
    }

    public func save(_ profile: Profile) async throws(StoreError) {
        try await update { $0 = profile }
    }

    @discardableResult
    public func update(_ change: @Sendable (inout Profile) -> Void) async throws(StoreError) -> Profile {
        let changes = changes
        let number = ChangeNumber()
        let saved = try await base.update { profile in
            change(&profile)
            number.set(changes.next())
        }
        let made = number.value
        if made > lastKept {
            lastKept = made
            keeper.keep(KeptProfileSettings(saved))
        }
        return saved
    }

    /// Delete my data: the settings are forgotten, then the rest of the profile is erased.
    public func eraseAll() async throws(StoreError) {
        // A change still on its way back is older than this, so it isn't kept afterwards.
        lastKept = changes.next()
        keeper.forget()
        try await base.eraseAll()
    }
}

/// Counts up, from any thread.
private final class ChangeCounter: Sendable {
    private let count = Mutex(0)

    func next() -> Int {
        count.withLock {
            $0 += 1
            return $0
        }
    }
}

/// One change's number, set while the wrapped store makes it.
private final class ChangeNumber: Sendable {
    private let stored = Mutex(0)

    var value: Int { stored.withLock { $0 } }

    func set(_ number: Int) {
        stored.withLock { $0 = number }
    }
}
