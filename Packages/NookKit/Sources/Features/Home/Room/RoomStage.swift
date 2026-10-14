import DesignSystem
import SwiftUI

/// Where everything in the room sits, in the mockup's stage units.
///
/// `screens/home.html` draws the room on a 390 x 844 stage at one unit per point. These rects
/// are copied from it, so the app and the mockup can be laid side by side. `RoomLayout` turns
/// them into points for the screen at hand.
nonisolated enum RoomStage {
    static let width: CGFloat = 390
    /// The floor line (`--floor-y`).
    static let floorY: CGFloat = 550

    /// The part of the stage that must be on screen: from the top of the title down to just
    /// below the hamper. The floor and the bed carry on under the tab bar.
    static let visibleTop: CGFloat = 40
    static let visibleBottom: CGFloat = 740
    static var visibleHeight: CGFloat { visibleBottom - visibleTop }

    // The title, left of the plant shelf.
    static let title = CGRect(x: 20, y: 44, width: 300, height: 38)

    // On the wall, back to front.
    static let window = CGRect(x: 170, y: 134, width: 81.6, height: 156.4)
    static let shelfTop = CGRect(x: 250, y: 46, width: 136.8, height: 99)
    static let shelfFrames = CGRect(x: 264.7, y: 151, width: 107.4, height: 89.8)
    static let calendar = CGRect(x: 203, y: 293, width: 90, height: 80)

    // The wardrobe (the whole thing opens Closet), with its rail, the flats and its plate.
    static let wardrobe = CGRect(x: -12, y: 124, width: 177.1, height: 425.5)
    static let wardrobeRail = CGRect(x: 14, y: 234, width: 136, height: 114)
    static let wardrobeFlats = CGRect(x: 20, y: 335, width: 34, height: 10)
    static let closetPlate = CGRect(x: 25, y: 169, width: 112, height: 44)

    // Her name sign; the name sits on the flat panel.
    static let sign = CGRect(x: 291, y: 247, width: 96.8, height: 56.3)
    static let signName = CGRect(x: 306, y: 270.8, width: 66.8, height: 22.8)

    // On the floor, back to front.
    static let rug = CGRect(x: 14, y: 566, width: 312, height: 152)
    static let desk = CGRect(x: 190, y: 440, width: 196, height: 160)
    static let laptop = CGRect(x: 226, y: 381.6, width: 92, height: 64)
    static let laptopScreen = CGRect(x: 232, y: 386.6, width: 80, height: 45)
    static let lamp = CGRect(x: 334, y: 365.6, width: 44, height: 80)
    static let chair = CGRect(x: 198, y: 493, width: 94, height: 112)
    /// Maya asleep on the rug, and her z's. Phase 5a draws her here.
    static let maya = CGRect(x: 142, y: 630, width: 110, height: 60)
    static let mayaZs = CGRect(x: 170, y: 604, width: 40, height: 40)

    // The suitcase where the rack stood: the Source control.
    static let suitcase = CGRect(x: 4, y: 430, width: 112, height: 190)
    static let suitcaseArt = CGRect(x: 8, y: 436, width: 104, height: 182)
    static let sourcePlate = CGRect(x: 8, y: 466, width: 104, height: 46)
    static let scopePlate = CGRect(x: 10, y: 517, width: 100, height: 40)

    // The hamper in front of the suitcase, at the rug's edge.
    static let hamper = CGRect(x: 12, y: 632, width: 92, height: 100)
    static let hamperArt = CGRect(x: 14, y: 636, width: 88, height: 96)
    static let laundryPlate = CGRect(x: 20, y: 676, width: 76, height: 40)

    // Plates and controls on the wall and the desk.
    static let savedLooks = CGRect(x: 252.4, y: 94, width: 132, height: 44)
    static let savedPlate = CGRect(x: 252.4, y: 101, width: 132, height: 30)
    static let framedLooks = CGRect(x: 266, y: 154, width: 104, height: 62)
    static let occasion = CGRect(x: 208, y: 313, width: 80, height: 45)
    /// The three desk drawers, top to bottom. Each drawer front is 80 x 44, 46 apart.
    static let drawers = [455.0, 501.0, 547.0].map { CGRect(x: 297, y: $0, width: 80, height: 44) }
    /// A drawer's plate, inside the drawer.
    static let drawerPlateInset = CGRect(x: 5, y: 5, width: 70, height: 24)

    /// The bed sits in the screen's bottom-right corner. Its top never rises above stage y 572,
    /// where the mockup's 844-point screen puts it, so it stays clear of the drawers.
    static let bedSize = CGSize(width: 118, height: 272)
    static let bedTop: CGFloat = 572

    /// The pitch between drawer fronts. Below this scale two drawers can't both have a 44 pt target.
    static let drawerPitch: CGFloat = 46
}

/// The stage scaled and placed for one screen.
///
/// The room scales to fit between the navigation bar and the tab bar, so the whole room shows
/// without scrolling. It never shrinks below the scale that keeps every control 44 points
/// tall; on a short phone (iPhone SE) it scrolls a little instead. The wall and the floor run
/// to both edges when the room is narrower than the screen.
nonisolated struct RoomLayout: Equatable, Sendable {
    /// The whole area the room draws in, including what sits under the bars.
    let size: CGSize
    /// The bars' heights: navigation bar at the top, tab bar at the bottom.
    let insets: EdgeInsets
    let scale: CGFloat
    /// Where stage x 0 lands.
    let originX: CGFloat
    /// Where stage y 0 lands.
    let originY: CGFloat
    /// The canvas height: the screen, or more when the room has to scroll.
    let contentHeight: CGFloat

    /// The smallest scale that still gives every control a 44 pt target.
    static let minimumScale = NookSpacing.minimumTapTarget / RoomStage.drawerPitch

    init(size: CGSize, insets: EdgeInsets) {
        self.size = size
        self.insets = insets
        let available = max(0, size.height - insets.top - insets.bottom)
        let widthScale = size.width / RoomStage.width
        let heightScale = available / RoomStage.visibleHeight
        // Fit the height, but keep targets big enough, and never wider than the screen.
        scale = max(0.01, min(widthScale, max(heightScale, Self.minimumScale)))
        originX = (size.width - RoomStage.width * scale) / 2
        originY = insets.top - RoomStage.visibleTop * scale
        contentHeight = max(size.height, insets.top + RoomStage.visibleHeight * scale + insets.bottom)
    }

    /// True when the room is taller than the screen and scrolls.
    var scrolls: Bool { contentHeight > size.height + 0.5 }

    /// A stage rect in points on the canvas.
    func rect(_ stage: CGRect) -> CGRect {
        CGRect(
            x: originX + stage.minX * scale,
            y: originY + stage.minY * scale,
            width: stage.width * scale,
            height: stage.height * scale
        )
    }

    /// A control's tap area: its stage rect, grown to at least 44 x 44 points around its centre.
    func target(_ stage: CGRect) -> CGRect {
        let frame = rect(stage)
        let width = max(frame.width, NookSpacing.minimumTapTarget)
        let height = max(frame.height, NookSpacing.minimumTapTarget)
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }

    var floorY: CGFloat { originY + RoomStage.floorY * scale }

    /// The bed, in the canvas's bottom-right corner. On a screen shorter than the mockup's, its
    /// foot runs off the bottom, under the tab bar.
    var bed: CGRect {
        let width = RoomStage.bedSize.width * scale
        let height = RoomStage.bedSize.height * scale
        let top = max(originY + RoomStage.bedTop * scale, contentHeight - height)
        return CGRect(x: size.width - width, y: top, width: width, height: height)
    }
}

extension View {
    /// Places a view on the room canvas at `frame` (top-left origin).
    func roomFrame(_ frame: CGRect) -> some View {
        self.frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}
