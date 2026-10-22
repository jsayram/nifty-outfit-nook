#if DEBUG
    import Foundation
    import Synchronization
    import UIKit

    /// Answers "can the store be opened while the phone is locked?" (`closet/DEVICE_TEST_CHECKLIST.md`
    /// 2.9). Debug builds only.
    ///
    /// When iOS says protected data is about to go away (the phone locked), the probe asks for a
    /// short background task, waits 15 seconds (iOS drops the keys for `complete` files about 10
    /// seconds after the lock), then tries to read the first bytes of `Nook.store`. A read that
    /// fails is the pass. It also notes when the phone unlocked. The notes are kept in memory for
    /// the Device checks screen, so the screen has to stay running (don't force-quit) between
    /// the lock and the unlock.
    public final class LockProbe: Sendable {
        public static let shared = LockProbe()

        private struct State {
            var started = false
            var lines: [String] = []
        }

        private let state = Mutex(State())

        /// How long to wait after the lock before reading. Tests shorten it.
        static let waitSeconds = 15.0

        /// Starts listening. Safe to call again.
        @MainActor public func start(storeURL: URL) {
            let first = state.withLock { state -> Bool in
                defer { state.started = true }
                return !state.started
            }
            guard first else { return }
            NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main
            ) { [self] _ in
                MainActor.assumeIsolated { locked(storeURL: storeURL) }
            }
            NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
            ) { [self] _ in
                note("Phone unlocked: protected data is available again.")
            }
        }

        public var lines: [String] {
            state.withLock { $0.lines }
        }

        private func note(_ text: String) {
            let time = Date.now.formatted(date: .omitted, time: .standard)
            state.withLock { $0.lines.append("\(time)  \(text)") }
        }

        @MainActor private func locked(storeURL: URL) {
            note("Phone locked: protected data is going away.")
            var task = UIBackgroundTaskIdentifier.invalid
            task = UIApplication.shared.beginBackgroundTask { [self] in
                note("iOS ended the app's background time before the check ran. Try again.")
            }
            Task { [self] in
                try? await Task.sleep(for: .seconds(Self.waitSeconds))
                let available = UIApplication.shared.isProtectedDataAvailable
                if available {
                    note("The phone was unlocked before the check. Lock it and wait a minute.")
                } else {
                    note(Self.readResult(storeURL: storeURL))
                }
                UIApplication.shared.endBackgroundTask(task)
            }
        }

        /// Tries to read the store's first bytes and says what happened. Reading is the fail.
        static func readResult(storeURL: URL) -> String {
            do {
                let handle = try FileHandle(forReadingFrom: storeURL)
                defer { try? handle.close() }
                let bytes = try handle.read(upToCount: 16)
                return (bytes?.isEmpty ?? true)
                    ? "Read of Nook.store returned nothing."
                    : "FAIL: Nook.store could be read \(Self.waitSeconds.formatted()) s after the lock."
            } catch {
                return "PASS: Nook.store could not be read \(Self.waitSeconds.formatted()) s after the lock."
            }
        }
    }
#endif
