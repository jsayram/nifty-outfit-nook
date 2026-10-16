import SwiftUI

/// A garment as a sticker: the piece with a thick white edge that follows its outline and a
/// soft shadow under it (RD-07, `.stk` in `results.html`). No tile, no hanger.
///
/// It takes exactly `size`, whatever the garment's shape: the piece is fitted inside, centred,
/// with room for the edge. The shadow falls outside that size, as a CSS drop shadow does, so it
/// never moves the layout. The edge and shadow grow with the size (`StickerSpec`).
///
/// The sticker is made once in the background and cached (`StickerCache`), so scrolling past it
/// only draws a picture. Until it's ready the space stays empty. In still images (snapshot
/// tests) it's made straight away. It's decoration: VoiceOver skips it, and the screen says
/// what the piece is in words.
public struct NookSticker: View {
    private let id: String
    private let size: CGSize
    private let source: StickerSource
    private let placement: StickerSpec.Placement

    @Environment(\.stickerCache) private var sharedCache
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.nookStaticRendering) private var isStatic
    @State private var shown: Shown?
    /// Used when no cache is in the environment, so the sticker still isn't made twice.
    @State private var ownCache: StickerCache?

    private struct Shown {
        let key: StickerCache.Key
        let artwork: StickerArtwork?
    }

    /// - Parameters:
    ///   - id: names the picture `source` gives, for the cache: the same `id` must always mean
    ///     the same picture.
    ///   - size: the space the sticker takes, in points.
    ///   - placement: centred in that space, or resting on its bottom.
    public init(_ id: String, size: CGSize, source: StickerSource, placement: StickerSpec.Placement = .centred) {
        self.id = id
        self.size = size
        self.source = source
        self.placement = placement
    }

    private var key: StickerCache.Key {
        StickerCache.Key(
            id: id,
            spec: StickerSpec(
                size: size, scale: displayScale, appearance: colorScheme == .dark ? .dark : .light,
                placement: placement))
    }

    public var body: some View {
        let key = key
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                if let artwork = artwork(for: key) {
                    Image(decorative: artwork.image, scale: artwork.spec.scale)
                        .resizable()
                        .frame(width: size.width + 2 * artwork.bleed, height: size.height + 2 * artwork.bleed)
                }
            }
            .task(id: key) {
                guard !isStatic, shown?.key != key else { return }
                let cache = cache
                if let kept = cache.cached(key) {
                    shown = Shown(key: key, artwork: kept)
                    return
                }
                let artwork = await cache.sticker(for: key, from: source)
                if !Task.isCancelled { shown = Shown(key: key, artwork: artwork) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var cache: StickerCache {
        if let sharedCache { return sharedCache }
        if let ownCache { return ownCache }
        let made = StickerCache(byteLimit: 8 << 20)
        ownCache = made
        return made
    }

    private func artwork(for key: StickerCache.Key) -> StickerArtwork? {
        if let shown, shown.key == key { return shown.artwork }
        if let kept = sharedCache?.cached(key) { return kept }
        guard isStatic else { return nil }
        // A still image can't wait for the background, so the sticker is made here.
        return (sharedCache ?? StickerCache(byteLimit: 8 << 20)).stickerNow(for: key, from: source)
    }
}
