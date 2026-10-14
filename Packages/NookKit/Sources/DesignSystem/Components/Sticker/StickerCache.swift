import CoreGraphics
import SwiftUI
import UIKit

/// Where a sticker's garment picture comes from.
nonisolated public enum StickerSource: Sendable {
    /// A picture already in hand, such as a cutout that has loaded.
    case image(CGImage)
    /// A picture drawn on demand for the sticker's size and appearance, such as a placeholder
    /// drawing. Called away from the main actor, or straight away when drawing a still image.
    case drawn(@Sendable (StickerSpec) -> CGImage?)

    /// The garment picture, made now.
    public func picture(for spec: StickerSpec) -> CGImage? {
        switch self {
        case .image(let image): image
        case .drawn(let draw): draw(spec)
        }
    }
}

/// Makes stickers once and keeps them, so a sticker on screen is only ever a cached picture.
///
/// Each sticker is made away from the main actor the first time it's asked for, and kept in
/// memory by its key: what it shows (`id`) plus its size, scale and appearance. Two views
/// asking for the same sticker at once share one render. The least recently used stickers go
/// first when the budget is full, and everything goes on a memory warning. Nothing is written
/// to disk: a sticker of her garment is Personal data, like the photo.
///
/// The `id` names the picture, not the garment: a cutout's photo reference, or a drawing's kind
/// and colours. A new photo has a new reference, so a sticker can never go stale, and pieces
/// that share a drawing share its sticker.
@MainActor
public final class StickerCache {
    public struct Key: Hashable, Sendable {
        public let id: String
        public let spec: StickerSpec

        public init(id: String, spec: StickerSpec) {
            self.id = id
            self.spec = spec
        }
    }

    private struct Entry {
        let artwork: StickerArtwork
        var lastUse: UInt64
    }

    /// The most memory the kept stickers may hold, in bytes.
    public let byteLimit: Int
    private var entries: [Key: Entry] = [:]
    private var misses: Set<Key> = []
    private var inFlight: [Key: Task<StickerArtwork?, Never>] = [:]
    private var useCounter: UInt64 = 0
    private var memoryWarning: (any NSObjectProtocol)?

    /// How many stickers were made, for tests.
    public private(set) var renderCount = 0
    /// The memory the kept stickers hold, in bytes.
    public private(set) var byteCount = 0
    /// How many stickers are kept.
    public var count: Int { entries.count }

    /// - Parameter byteLimit: 48 MB holds about 20 detail-sized stickers at 3x, or about 150
    ///   closet-sized ones.
    public init(byteLimit: Int = 48 << 20) {
        self.byteLimit = byteLimit
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
    }

    isolated deinit {
        if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) }
    }

    /// The sticker for `key` if it's kept, without making it.
    public func cached(_ key: Key) -> StickerArtwork? {
        guard var entry = entries[key] else { return nil }
        useCounter += 1
        entry.lastUse = useCounter
        entries[key] = entry
        return entry.artwork
    }

    /// True when the source for `key` had no picture, so asking again would draw nothing.
    public func isMissing(_ key: Key) -> Bool { misses.contains(key) }

    /// The sticker for `key`: kept, already being made, or made now in the background.
    public func sticker(for key: Key, from source: StickerSource) async -> StickerArtwork? {
        if let kept = cached(key) { return kept }
        if misses.contains(key) { return nil }
        if let running = inFlight[key] { return await running.value }

        renderCount += 1
        let task = Task { await Self.make(source, spec: key.spec) }
        inFlight[key] = task
        let artwork = await task.value
        inFlight[key] = nil
        store(artwork, for: key)
        return artwork
    }

    /// Makes the sticker for `key` straight away on the calling thread and keeps it. Only for
    /// still images (the snapshot tests and the catalog's), where nothing can wait.
    public func stickerNow(for key: Key, from source: StickerSource) -> StickerArtwork? {
        if let kept = cached(key) { return kept }
        if misses.contains(key) { return nil }
        renderCount += 1
        let artwork = source.picture(for: key.spec).flatMap { StickerRenderer.render($0, spec: key.spec) }
        store(artwork, for: key)
        return artwork
    }

    /// Forgets every kept sticker. Ones being made still finish.
    public func removeAll() {
        entries.removeAll()
        misses.removeAll()
        byteCount = 0
    }

    private func store(_ artwork: StickerArtwork?, for key: Key) {
        guard let artwork else {
            misses.insert(key)
            return
        }
        if let old = entries[key] { byteCount -= old.artwork.byteCount }
        useCounter += 1
        entries[key] = Entry(artwork: artwork, lastUse: useCounter)
        byteCount += artwork.byteCount
        // Least recently used first. Linear, but the cache holds at most a few hundred.
        while byteCount > byteLimit, entries.count > 1,
            let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse })
        {
            byteCount -= oldest.value.artwork.byteCount
            entries[oldest.key] = nil
        }
    }

    @concurrent
    nonisolated private static func make(_ source: StickerSource, spec: StickerSpec) async -> StickerArtwork? {
        guard let picture = source.picture(for: spec) else { return nil }
        return StickerRenderer.render(picture, spec: spec)
    }
}

extension EnvironmentValues {
    /// The stickers every screen shares, made once at the root. Without one, a sticker is made
    /// for its view alone.
    @Entry public var stickerCache: StickerCache?
}
