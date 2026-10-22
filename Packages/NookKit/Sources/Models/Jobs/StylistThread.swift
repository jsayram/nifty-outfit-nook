import Foundation
import Synchronization

/// One Ask stylist conversation about one look (Phase 27c), kept so she can leave and come back.
/// Her question and the stylist's answers, in order. The screen itself isn't built yet (a question
/// for Jose); the endpoint (27a), this model, its store and the job that answers a question are.
///
/// Data tier: **Personal** (her own words about her clothes). Kept in the store on the iPhone,
/// carried by an export like her looks, and erased by Delete my data. Only the last six turns go
/// with a new question (`StyleCall.question`).
public struct StylistThread: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<StylistThread>

    public struct Turn: Identifiable, Hashable, Sendable, Codable {
        public typealias ID = EntityID<Turn>

        public enum From: String, Hashable, Sendable, Codable {
            case her, stylist
        }

        public let id: ID
        public var from: From
        public var text: String
        /// Pieces the stylist's answer mentions, by ID. Empty for her turns.
        public var pieces: [Garment.ID]
        public var at: Date

        public init(id: ID = .random(), from: From, text: String, pieces: [Garment.ID] = [], at: Date) {
            self.id = id
            self.from = from
            self.text = text
            self.pieces = pieces
            self.at = at
        }
    }

    public let id: ID
    /// The look the conversation is about.
    public var lookID: Look.ID
    public var turns: [Turn]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: ID = .random(), lookID: Look.ID, turns: [Turn] = [], createdAt: Date) {
        self.id = id
        self.lookID = lookID
        self.turns = turns
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    /// At most this many turns are kept per conversation; the oldest go first.
    public static let maximumTurns = 60
    /// At most this many characters in one turn (the contract's question limit is lower).
    public static let maximumTurnLength = 2_000

    /// Adds a turn, keeping the conversation within its limits.
    public mutating func append(_ turn: Turn) {
        var turn = turn
        turn.text = String(turn.text.prefix(Self.maximumTurnLength))
        turns.append(turn)
        if turns.count > Self.maximumTurns { turns.removeFirst(turns.count - Self.maximumTurns) }
        updatedAt = max(updatedAt, turn.at)
    }
}

/// Where Ask stylist conversations are kept. Erased by Delete my data.
public protocol StylistThreadStore: ErasableStore {
    func threads() async throws(StoreError) -> [StylistThread]
    func thread(_ id: StylistThread.ID) async throws(StoreError) -> StylistThread?
    func save(_ thread: StylistThread) async throws(StoreError)
    func delete(_ id: StylistThread.ID) async throws(StoreError)
}

extension StylistThreadStore {
    /// The conversation about this look, newest first if there are several.
    public func thread(about look: Look.ID) async throws(StoreError) -> StylistThread? {
        try await threads().filter { $0.lookID == look }.max { $0.updatedAt < $1.updatedAt }
    }
}

/// Conversations in memory: previews, tests and the debug sample closet.
public final class InMemoryStylistThreadStore: StylistThreadStore {
    private let state: Mutex<[StylistThread.ID: StylistThread]>

    public init(_ threads: [StylistThread] = []) {
        state = Mutex(Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }))
    }

    public func threads() async throws(StoreError) -> [StylistThread] {
        state.withLock { Array($0.values) }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func thread(_ id: StylistThread.ID) async throws(StoreError) -> StylistThread? {
        state.withLock { $0[id] }
    }

    public func save(_ thread: StylistThread) async throws(StoreError) { state.withLock { $0[thread.id] = thread } }
    public func delete(_ id: StylistThread.ID) async throws(StoreError) { state.withLock { $0[id] = nil } }
    public func eraseAll() async throws(StoreError) { state.withLock { $0 = [:] } }
}
