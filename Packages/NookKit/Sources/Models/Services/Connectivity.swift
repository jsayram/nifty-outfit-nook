import Foundation

// Whether the phone can reach the internet (Phase 26, PRD 11.7). Only cloud features care: her
// closet, looks and photos work with no connection at all. The state is a hint for a calm banner
// and a quicker retry, never a gate: a request is still sent when the state says offline, because
// the system's answer can lag behind a connection that just came back.

public enum ConnectionState: Sendable, Equatable {
    /// Nothing reported yet, as at launch before the first update. Treated as online.
    case unknown
    case online
    case offline
}

/// Where connection changes come from: the system's path monitor in the app, a stand-in in tests.
public protocol ConnectivitySource: Sendable {
    /// The current state first, then every change. Ends when the consumer stops listening.
    func states() -> AsyncStream<ConnectionState>
}

/// A source that reports one state and never changes. For previews and tests.
public struct FixedConnectivitySource: ConnectivitySource {
    private let state: ConnectionState

    public init(_ state: ConnectionState) { self.state = state }

    public func states() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            continuation.yield(state)
            continuation.finish()
        }
    }
}
