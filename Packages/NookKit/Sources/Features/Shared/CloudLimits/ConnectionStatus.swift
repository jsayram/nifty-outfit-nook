import DesignSystem
import Models
import Observation
import SwiftUI

/// Whether the phone is online, for the calm offline banner where the cloud is needed (Phase 26,
/// PRD 11.7). The app starts one at launch and follows the system's path monitor; screens read it
/// from the environment. It only informs: a request is still sent when it says offline, and her
/// closet never looks at it.
@Observable
public final class ConnectionStatus {
    public private(set) var state: ConnectionState

    public init(_ state: ConnectionState = .unknown) {
        self.state = state
    }

    /// What screens read where nothing set a state: unknown, which counts as online.
    public static let unreported = ConnectionStatus()

    public var isOffline: Bool { state == .offline }

    public func set(_ state: ConnectionState) {
        self.state = state
    }

    /// Follows `source` until the calling task is cancelled (SwiftUI's `.task` does that when the
    /// view goes away).
    public func follow(_ source: some ConnectivitySource) async {
        for await state in source.states() {
            self.state = state
        }
    }
}

extension EnvironmentValues {
    /// The app's connection state. Unknown, which counts as online, where nothing sets it.
    @Entry public var connection = ConnectionStatus.unreported
}

/// "You're offline." where a cloud feature needs the connection, with what still works. Shows
/// nothing while online. Appearing is announced to VoiceOver, once, so it isn't missed.
public struct CloudOfflineBanner: View {
    @Environment(\.connection) private var connection
    private let detail: String
    private let retry: (() -> Void)?

    public init(detail: String? = nil, retry: (() -> Void)? = nil) {
        self.detail = detail ?? CloudProblemText.offlineDetail
        self.retry = retry
    }

    public var body: some View {
        Group {
            if connection.isOffline {
                NookOfflineBanner(detail: detail, retry: retry)
                    .accessibilityIdentifier("cloudOfflineBanner")
            }
        }
        .onChange(of: connection.isOffline) { _, offline in
            if offline { CloudProblemText.announce(CloudProblemText.message(for: .offline) ?? detail) }
        }
    }
}
