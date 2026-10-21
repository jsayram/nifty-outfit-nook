import Foundation
import Models
import Network

/// `ConnectivitySource` over `NWPathMonitor`: online when the system has a usable route (Wi-Fi,
/// cellular or wired), offline when it has none. Low Data Mode and an expensive link still count
/// as online, because our calls are small. One monitor per listener, stopped when it stops
/// listening.
public struct PathConnectivitySource: ConnectivitySource {
    public init() {}

    public func states() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(Self.state(for: path.status))
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "com.jsayram.niftyoutfitnook.connectivity"))
        }
    }

    static func state(for status: NWPath.Status) -> ConnectionState {
        switch status {
        case .satisfied: .online
        case .unsatisfied: .offline
        // Needs a connection to be started (a VPN on demand): the request itself will start it.
        case .requiresConnection: .unknown
        @unknown default: .unknown
        }
    }
}
