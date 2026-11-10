import Models

/// How an in-memory store behaves: how long each call waits, and whether it fails.
public struct StoreOptions: Hashable, Sendable {
    public var latency: Duration
    /// Every call throws `StoreError.unavailable`.
    public var fails: Bool
    /// Which store this is, for the debug faults' scopes (`closet`, `looks`...). Each store names
    /// itself.
    public var store = ""
    #if DEBUG
        /// N4: `-hold` and `-fail` for this store's calls (`DebugFaults.storeScopes`). None by default;
        /// the fixture services pass the launch's.
        public var faults = DebugFaults.none
    #endif

    public init(latency: Duration = .zero, fails: Bool = false) {
        self.latency = latency
        self.fails = fails
    }

    /// The same options for the store called `name`.
    func named(_ name: String) -> StoreOptions {
        var options = self
        options.store = name
        return options
    }

    /// Waits for the latency, then fails if asked to. Called at the start of every store call, with
    /// the call's own name.
    func begin(_ method: String = #function) async throws(StoreError) {
        if latency > .zero {
            do {
                try await Task.sleep(for: latency)
            } catch {
                throw .cancelled
            }
        }
        #if DEBUG
            if let fault = await faults.fault(for: DebugFaults.storeScopes(store: store, method: method)) {
                switch fault {
                case .cancelled: throw .cancelled
                case .fail: throw .unavailable
                }
            }
        #endif
        if Task.isCancelled { throw .cancelled }
        if fails { throw .unavailable }
    }
}
