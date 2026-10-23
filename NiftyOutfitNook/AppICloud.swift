import Foundation
import Models
import Services
import Synchronization
import UIKit

/// Private iCloud sync (Phase 21b, decision 0004 §5): on only in a build made with
/// `NOOK_ICLOUD = YES`, once Jose has made the container and the CloudKit schema. Until then no
/// iCloud row shows, nothing talks to CloudKit, and Delete my data has no iCloud part. See
/// `docs/icloud.md` for the switch.
nonisolated enum AppICloud {
    /// `NOOK_ICLOUD = YES` in the build settings (Configs/Base.xcconfig) puts this in Info.plist.
    static let isEnabled = Bundle.main.object(forInfoDictionaryKey: "NookICloudEnabled") as? String == "YES"
    static let containerIdentifier = "iCloud.com.jsayram.niftyoutfitnook"

    private static let made = Mutex<ICloudSync?>(nil)

    /// The one sync engine for her own closet's store, made and started the first time it's
    /// asked for, or `nil` in a build without iCloud. `erase` is Delete my data on this iPhone,
    /// for "Delete it here too".
    static func sync(storage: NookStorage, erase: @escaping @Sendable () async -> Bool) -> ICloudSync? {
        guard isEnabled, let location = storage.backupLocation else { return nil }
        return made.withLock { made in
            if let made { return made }
            let sync = ICloudSync(
                storage: storage, location: location,
                engine: CloudKitSyncEngine.maker(containerIdentifier: containerIdentifier), eraseThisDevice: erase)
            made = sync
            start(sync)
            return sync
        }
    }

    /// At launch: a pending iCloud deletion first, then sync if it's on. Afterwards it looks for
    /// changes a few seconds after her edits settle and whenever the app comes forward. The
    /// engine also syncs on its own, woken by CloudKit's silent pushes.
    private static func start(_ sync: ICloudSync) {
        let settle = SettleTimer(sync: sync)
        _ = StoreSaveSignal.listen { Task { await settle.poke() } }
        Task { @MainActor in
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in
                Task { await sync.syncNow() }
            }
            UIApplication.shared.registerForRemoteNotifications()
            await sync.start()
        }
    }

    /// Waits for edits to settle before looking for changes, so a burst of saves is one sync.
    private actor SettleTimer {
        let sync: ICloudSync
        private var pending: Task<Void, Never>?

        init(sync: ICloudSync) { self.sync = sync }

        func poke() {
            pending?.cancel()
            pending = Task { [sync] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await sync.syncNow()
            }
        }
    }
}
