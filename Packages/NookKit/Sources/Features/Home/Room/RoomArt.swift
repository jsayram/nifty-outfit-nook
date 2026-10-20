import Models
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
    // Suitcases (Phase 13). The five drawings a suitcase can have, each 104 x 182 with the same
    // plain face at y 30 to 124, where the hall's luggage tags and Home's plates sit.
    case suitcaseRolling = "suitcase-rolling"
    case suitcaseWeekender = "suitcase-weekender"
    case suitcaseDuffel = "suitcase-duffel"
    case suitcaseBackpack = "suitcase-backpack"
    case suitcaseTote = "suitcase-tote"
    /// The entry hall behind the favourites on Suitcases.
    case hallDoor = "travel-hall-door"
    case hallHooks = "travel-hall-hooks"
    case hallPeg = "travel-hall-peg"
    case hallMirror = "travel-hall-mirror"
    case hallConsole = "travel-hall-console"
    case hallRunner = "travel-hall-runner"
    // Laundry's corner (Phase 13), with the hamper from Home.
    case washer = "travel-washer"
    case laundryShelf = "travel-laundry-shelf"
    case floorPlant = "plant-floor"
    // The desk's three drawers as a small chest, with one drawer pulled open, on Help, Send
    // feedback and Privacy and terms (Phase 14b). Each is 136 x 156, feet at y 148.
    case drawersHelp = "acct-drawers-help"
    case drawersFeedback = "acct-drawers-feedback"
    case drawersPrivacy = "acct-drawers-privacy"
    // The porch on the welcome screen (Phase 17, `onboarding.html`).
    /// The roof's edge, 390 x 54, tiled across the window.
    case welcomeRoof = "welcome-roof"
    /// The house's siding boards and skirt, 390 x 432, stretched across the window.
    case welcomeSiding = "welcome-siding"
    case welcomeClouds = "welcome-clouds"
    case welcomeDoor = "welcome-door"
    case welcomeLantern = "welcome-lantern"
    case welcomeMat = "welcome-mat"
    case welcomePots = "welcome-pots"
    case porchBench = "acct-porch-bench"
    case porchSneakers = "chat-sneakers"
}

nonisolated extension SuitcaseIcon {
    /// The drawing that stands for a suitcase in the hall, on its rows and on Home.
    nonisolated var art: RoomArt {
        switch self {
        case .rolling: .suitcaseRolling
        case .weekender: .suitcaseWeekender
        case .duffel: .suitcaseDuffel
        case .backpack: .suitcaseBackpack
        case .tote: .suitcaseTote
        }
    }
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
