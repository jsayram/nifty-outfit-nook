import SwiftUI

/// The room's drawings in `Room.xcassets`. Each is a vector image with a light and a dark
/// version, built from the mockup art by `scripts/room-art.py` (see `art/room/README.md`).
nonisolated enum RoomArt: String, CaseIterable, Sendable {
    case bed
    case calendar
    case chair
    case desk = "home-desk"
    case flats = "home-flats"
    /// The hamper, empty: tracking on and nothing to wash (RD-11).
    case hamper = "home-hamper"
    /// The empty hamper, faded: laundry tracking is off.
    case hamperFaded = "home-hamper-faded"
    /// A few pieces to wash: a low heap just above the rim.
    case hamperSome = "home-hamper-dirty"
    /// Many pieces to wash: a taller heap and a sleeve over the rim. Drawn 14 units taller.
    case hamperFull = "home-hamper-full"
    case lamp = "home-lamp"
    case suitcase = "home-suitcase"
    case laptop
    /// Maya asleep, in her own apricot colours (RD-12).
    case maya
    case nameSign = "name-sign"
    case rug
    case shelfFrames = "shelf-frames"
    case shelfTop = "shelf-top"
    case wardrobeRail = "wardrobe-rail"
    case wardrobe
    // The window for each weather, night, and a plain one when the weather isn't known (RD-01.4).
    case windowSun = "window-sun"
    case windowCloudy = "window-cloudy"
    case windowRain = "window-rain"
    case windowSnow = "window-snow"
    case windowNight = "window-night"
    case windowPlain = "window-plain"
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
