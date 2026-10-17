import Models
import Synchronization

/// Kept profile settings in memory, standing in for the app's `UserDefaults` suite in tests and
/// previews: one keeper shared by two launches acts like one install.
public final class InMemoryProfileSettingsKeeper: ProfileSettingsKeeper {
    private let stored: Mutex<KeptProfileSettings>

    public init(_ settings: KeptProfileSettings = .none) {
        stored = Mutex(settings)
    }

    public func kept() -> KeptProfileSettings {
        stored.withLock { $0 }
    }

    public func keep(_ settings: KeptProfileSettings) {
        stored.withLock { $0 = settings }
    }

    public func forget() {
        stored.withLock { $0 = .none }
    }
}
