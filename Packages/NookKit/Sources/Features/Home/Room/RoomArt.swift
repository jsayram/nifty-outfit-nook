import SwiftUI

/// The room's drawings in `Room.xcassets`. Each is a vector image with a light and a dark
/// version, built from the mockup art by `scripts/room-art.py` (see `art/room/README.md`).
/// Closet's small drawings (its armoire and its tiles) live here too, from the same pipeline.
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
    // Closet (Phase 6).
    /// The open armoire in Closet's header, empty.
    case closetArmoire = "closet-armoire"
    /// The clothes inside it, in their own colours. Drawn over the armoire at the same size.
    case closetArmoireClothes = "closet-armoire-clothes"
    /// The small travel case on the Suitcases tile.
    case closetSuitcase = "closet-suitcase"
    /// The laundry basket on the Laundry tile, with clothes in it.
    case closetBasket = "closet-basket"
    /// The laundry basket, empty: all clean.
    case closetBasketEmpty = "closet-basket-empty"
    /// A rail of empty hangers, above the empty closet's message.
    case closetEmptyHangers = "closet-empty-hangers"
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
