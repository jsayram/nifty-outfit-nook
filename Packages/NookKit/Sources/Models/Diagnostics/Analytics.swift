import Foundation
import Synchronization

// Opt-in improvement analytics (PRD 23; D24, 29 October 2026): "Help improve the app", off by
// default, with no on-device counters. Only events from a fixed list leave the phone, each with an
// outcome from a fixed list, a coarse hour, the app and iOS version, the device class and the
// consent version, under a random ID she can reset. Never what she types, photos, measurements or
// weight, closet contents, garment IDs, looks, a location, her account or a transaction ID.
//
// Events wait in memory only (at most 100 or 64 KB, each dropped after 7 days) and are sent with
// no account token, so the server can't link them to her (F1c: POST /v1/analytics/events). They go
// at launch and then on a timer, and only once their hour is over, never right after the event:
// the server's own row times are finer than the hour (THREAT_MODEL, the F1b timing note).

/// The events the app may send (PRD 23.1's Styling family to start). Adding one is a change to the
/// allowlist, here and on the server.
public enum AnalyticsEvent: String, CaseIterable, Codable, Sendable {
    /// A Style Me request ended (`AIJobs`).
    case styleFinished
    /// An Ask stylist question ended.
    case askFinished
    /// A try-on picture ended.
    case tryOnFinished
}

/// How an event ended. Never a message, a count of her things or an ID.
public enum AnalyticsOutcome: String, CaseIterable, Codable, Sendable {
    case none
    case succeeded
    case failed
    case cancelled
}

/// iPhone or iPad, never the model.
public enum AnalyticsDeviceClass: String, Codable, Sendable {
    case iPhone
    case iPad
}

/// What every event carries about the app, set once at launch.
public struct AnalyticsContext: Hashable, Sendable {
    public var appVersion: String
    public var systemVersion: String
    public var deviceClass: AnalyticsDeviceClass

    public init(appVersion: String, systemVersion: String, deviceClass: AnalyticsDeviceClass) {
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.deviceClass = deviceClass
    }
}

/// One event as it would be sent: only these fields, all from fixed lists or short versions.
public struct AnalyticsRecord: Hashable, Sendable, Codable {
    public var event: AnalyticsEvent
    public var outcome: AnalyticsOutcome
    /// The start of the UTC hour it happened in, never the minute.
    public var hour: Date
    public var appVersion: String
    public var systemVersion: String
    public var deviceClass: AnalyticsDeviceClass
    public var consentVersion: String
    /// The random ID she can reset. Never joined to her account.
    public var analyticsID: String

    public init(
        event: AnalyticsEvent, outcome: AnalyticsOutcome, hour: Date, appVersion: String, systemVersion: String,
        deviceClass: AnalyticsDeviceClass, consentVersion: String, analyticsID: String
    ) {
        self.event = event
        self.outcome = outcome
        self.hour = hour
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.deviceClass = deviceClass
        self.consentVersion = consentVersion
        self.analyticsID = analyticsID
    }

    /// Roughly what one record takes when sent, for the 64 KB cap.
    static let estimatedBytes = 256
}

/// Her choice and the random ID, kept on the iPhone.
///
/// Data tier: **Personal** (pseudonymous). Erased by Delete my data.
public struct AnalyticsSettings: Codable, Hashable, Sendable {
    /// The consent text in this app version (closet `compliance/IN_APP_PRIVACY_TEXT.md`).
    public static let currentVersion = "analytics-1"

    public var version: String
    public var agreedAt: Date
    public var analyticsID: String

    public init(version: String = AnalyticsSettings.currentVersion, agreedAt: Date, analyticsID: String) {
        self.version = version
        self.agreedAt = agreedAt
        self.analyticsID = analyticsID
    }

    public var isCurrent: Bool { version == Self.currentVersion }
}

/// Where her analytics choice is kept. `nil` means off.
public protocol AnalyticsSettingsStore: ErasableStore {
    func current() -> AnalyticsSettings?
    func save(_ settings: AnalyticsSettings?)
}

/// In memory: previews, tests and the debug sample closet.
public final class InMemoryAnalyticsSettingsStore: AnalyticsSettingsStore {
    private let state: Mutex<AnalyticsSettings?>

    public init(_ settings: AnalyticsSettings? = nil) {
        state = Mutex(settings)
    }

    public func current() -> AnalyticsSettings? { state.withLock { $0 } }
    public func save(_ settings: AnalyticsSettings?) { state.withLock { $0 = settings } }
    public func eraseAll() async throws(StoreError) { state.withLock { $0 = nil } }
}

/// The server's analytics endpoint, as the app sees it. Sent with no account token.
public protocol AnalyticsEndpoint: Sendable {
    /// Sends a batch. Throws when it didn't go, so the events stay queued, or
    /// `AnalyticsBatchRefused` when the server won't ever take it, so they're dropped.
    func send(_ records: [AnalyticsRecord]) async throws
    /// Delete my analytics data: removes the events the server keeps under `analyticsID`.
    func deleteEvents(analyticsID: String) async throws
}

/// The server refused a batch for good (it doesn't match the contract or the consent): sending it
/// again would be refused again, so its events are dropped rather than kept.
public struct AnalyticsBatchRefused: Error, Equatable {
    public init() {}
}

/// No backend (previews, tests, a build without one): nothing is sent, so there is nothing to
/// delete.
public struct NoAnalyticsEndpoint: AnalyticsEndpoint {
    public struct NotAvailable: Error {
        public init() {}
    }

    public init() {}
    public func send(_ records: [AnalyticsRecord]) async throws { throw NotAvailable() }
    public func deleteEvents(analyticsID: String) async throws {}
}

/// "Help improve the app", as the screens and the rest of the app see it.
public protocol AnalyticsService: ErasableStore {
    var isOn: Bool { get }
    /// Turning it on makes a new random ID; turning it off clears unsent events at once.
    func setOn(_ on: Bool)
    /// Queues an event only while it's on. Never blocks and never fails.
    func record(_ event: AnalyticsEvent, _ outcome: AnalyticsOutcome)
    /// Sends the queued events whose hour is over, if any. Nothing is lost if it can't.
    func flush() async
    /// A new random ID, and the unsent events are cleared.
    func resetID()
    /// Asks the server to delete her events under the current ID, then resets the ID. Returns
    /// whether the server confirmed.
    func deleteMyData() async -> Bool
}

extension AnalyticsService {
    /// Sends at once (at launch) and then every `interval` until the task is cancelled. Never
    /// called from `record`, so an event never goes out the moment it happens.
    public func sendRegularly(every interval: Duration = OptInAnalytics.sendInterval) async {
        while !Task.isCancelled {
            await flush()
            try? await Task.sleep(for: interval)
        }
    }
}

/// The queue in memory and her choice in `settings` (PRD 23.1).
public final class OptInAnalytics: AnalyticsService {
    public static let maximumEvents = 100
    public static let maximumBytes = 64 * 1_024
    public static let keptFor: TimeInterval = 7 * 24 * 60 * 60
    /// How often the app sends while it's open, besides at launch.
    public static let sendInterval: Duration = .seconds(3_600)

    private let settings: any AnalyticsSettingsStore
    private let endpoint: any AnalyticsEndpoint
    private let context: AnalyticsContext
    private let now: @Sendable () -> Date
    private let queue = Mutex<[AnalyticsRecord]>([])

    public init(
        settings: any AnalyticsSettingsStore, endpoint: any AnalyticsEndpoint = NoAnalyticsEndpoint(),
        context: AnalyticsContext, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.endpoint = endpoint
        self.context = context
        self.now = now
    }

    public var isOn: Bool { settings.current()?.isCurrent == true }

    public func setOn(_ on: Bool) {
        queue.withLock { $0.removeAll() }
        settings.save(on ? AnalyticsSettings(agreedAt: now(), analyticsID: Self.newID()) : nil)
    }

    public func record(_ event: AnalyticsEvent, _ outcome: AnalyticsOutcome = .none) {
        guard let current = settings.current(), current.isCurrent else { return }
        let time = now()
        let record = AnalyticsRecord(
            event: event, outcome: outcome, hour: Self.hour(of: time), appVersion: context.appVersion,
            systemVersion: context.systemVersion, deviceClass: context.deviceClass,
            consentVersion: current.version, analyticsID: current.analyticsID)
        queue.withLock { queued in
            queued.removeAll { time.timeIntervalSince($0.hour) > Self.keptFor }
            queued.append(record)
            let limit = min(Self.maximumEvents, Self.maximumBytes / AnalyticsRecord.estimatedBytes)
            if queued.count > limit { queued.removeFirst(queued.count - limit) }
        }
    }

    /// What's waiting to be sent, oldest first.
    public var queued: [AnalyticsRecord] { queue.withLock { $0 } }

    public func flush() async {
        guard isOn else { return }
        // Only hours that are over: the arrival then says nothing finer than the hour already does.
        let time = now()
        let batch = queue.withLock { queued in queued.filter { time.timeIntervalSince($0.hour) >= 3_600 } }
        guard !batch.isEmpty else { return }
        do {
            try await endpoint.send(batch)
            queue.withLock { queued in queued.removeAll { batch.contains($0) } }
        } catch is AnalyticsBatchRefused {
            queue.withLock { queued in queued.removeAll { batch.contains($0) } }
        } catch {
            // Kept for the next try, within the same limits.
        }
    }

    public func resetID() {
        guard var current = settings.current() else { return }
        queue.withLock { $0.removeAll() }
        current.analyticsID = Self.newID()
        settings.save(current)
    }

    public func deleteMyData() async -> Bool {
        guard let current = settings.current() else { return true }
        do {
            try await endpoint.deleteEvents(analyticsID: current.analyticsID)
        } catch {
            return false
        }
        resetID()
        return true
    }

    public func eraseAll() async throws(StoreError) {
        queue.withLock { $0.removeAll() }
        try await settings.eraseAll()
    }

    static func newID() -> String { UUID().uuidString.lowercased() }

    static func hour(of date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600)
    }
}
