import Models

/// How an in-memory store behaves: how long each call waits, and whether it fails.
public struct StoreOptions: Hashable, Sendable {
    public var latency: Duration
    /// Every call throws `StoreError.unavailable`.
    public var fails: Bool

    public init(latency: Duration = .zero, fails: Bool = false) {
        self.latency = latency
        self.fails = fails
    }

    /// Waits for the latency, then fails if asked to. Called at the start of every store call.
    func begin() async throws(StoreError) {
        if latency > .zero {
            do {
                try await Task.sleep(for: latency)
            } catch {
                throw .cancelled
            }
        }
        if Task.isCancelled { throw .cancelled }
        if fails { throw .unavailable }
    }
}
