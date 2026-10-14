import SwiftUI

/// The room's drawings in `Room.xcassets`. Each is a vector image with a light and a dark
/// version, built from the mockup art by `scripts/room-art.py` (see `art/room/README.md`).
nonisolated enum RoomArt: String, CaseIterable, Sendable {
    case bed
    case calendar
    case chair
    case desk = "home-desk"
    case flats = "home-flats"
    case hamper = "home-hamper"
    case lamp = "home-lamp"
    case suitcase = "home-suitcase"
    case laptop
    case nameSign = "name-sign"
    case rug
    case shelfFrames = "shelf-frames"
    case shelfTop = "shelf-top"
    case wardrobeRail = "wardrobe-rail"
    case wardrobe
    /// The window on a rainy day. Phase 5a adds the other weather and night (RD-01.4).
    case windowRain = "window-rain"
}

/// A room drawing, stretched to the frame it's given. Decorative: hidden from VoiceOver, since
/// the control it belongs to carries the words.
struct RoomArtImage: View {
    let art: RoomArt

    init(_ art: RoomArt) {
        self.art = art
    }

    var body: some View {
        Image(decorative: art.rawValue, bundle: .module)
            .resizable()
            .interpolation(.high)
    }
}
