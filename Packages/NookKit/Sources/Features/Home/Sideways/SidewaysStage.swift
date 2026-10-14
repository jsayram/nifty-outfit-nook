import DesignSystem
import SwiftUI

/// Where everything sits in the sideways room, in the units of `home-landscape.html`.
///
/// The mockup doesn't squash the upright room into the short screen. It draws a closer view at
/// 0.72 of the upright drawings, rearranged to fit a 430 x 390 scene: wardrobe, window, sign,
/// calendar, desk, suitcase, hamper and Maya. These rects are copied from it. There's no shelf
/// and no bed; Saved Looks is the tab, and the scene's right edge meets the controls.
nonisolated enum SidewaysStage {
    static let width: CGFloat = 430
    static let height: CGFloat = 390
    /// The floor line (`--floor-y`).
    static let floorY: CGFloat = 290
    /// The lowest drawing that has to show: Maya's bottom edge. The rug runs on below.
    static let visibleBottom: CGFloat = 372

    /// The upright drawings' size here.
    static let artScale: CGFloat = 0.72

    static let rug = CGRect(x: 70, y: 300, width: 224.6, height: 109.4)
    static let wardrobe = CGRect(x: 8, y: 6, width: 118.1, height: 283.7)
    static let window = CGRect(x: 150, y: 20, width: 69.1, height: 132.5)
    static let sign = CGRect(x: 232, y: 58, width: 79.2, height: 46.1)
    /// The panel her name sits on, inside the sign.
    static let signName = CGRect(x: 244.2, y: 77.4, width: 54.8, height: 18.8)
    static let calendar = CGRect(x: 228, y: 118, width: 64.8, height: 57.6)
    static let lampGlow = CGRect(x: 348, y: 108, width: 96, height: 96)
    static let desk = CGRect(x: 272, y: 182, width: 141.1, height: 115.2)
    /// The drawer fronts, top to bottom.
    static let drawers = [193.0, 226.0, 259.0].map { CGRect(x: 349, y: $0, width: 58, height: 31) }
    static let laptop = CGRect(x: 302, y: 140, width: 66.2, height: 46.1)
    static let laptopScreen = CGRect(x: 306.3, y: 143.6, width: 57.6, height: 32.4)
    static let lamp = CGRect(x: 378, y: 128, width: 31.7, height: 57.6)
    static let chair = CGRect(x: 277, y: 218, width: 67.7, height: 80.6)
    static let maya = CGRect(x: 170, y: 326, width: 79.2, height: 43.2)
    static let mayaZs = CGRect(x: 192, y: 306, width: 28.8, height: 28.8)
    static let suitcase = CGRect(x: 112, y: 168, width: 74.9, height: 131)
    /// The empty, faded and low-heap hampers. The full one is drawn taller (`hamperArt(_:)`).
    static let hamper = CGRect(x: 40, y: 296, width: 63.4, height: 69.1)

    /// A drawing that sits on the upright room's wardrobe (the rail, the flats), placed on this
    /// wardrobe at the same spot.
    static func onWardrobe(_ upright: CGRect) -> CGRect {
        let scale = wardrobe.width / RoomStage.wardrobe.width
        return CGRect(
            x: wardrobe.minX + (upright.minX - RoomStage.wardrobe.minX) * scale,
            y: wardrobe.minY + (upright.minY - RoomStage.wardrobe.minY) * scale,
            width: upright.width * scale,
            height: upright.height * scale)
    }

    /// The hamper drawing for a look. The full one reaches higher, as in the upright room, so the
    /// basket lands in the same place.
    static func hamperArt(_ look: HamperLook) -> CGRect {
        guard look == .full else { return hamper }
        let extra = (RoomStage.hamperFullArt.height - RoomStage.hamperArt.height) * artScale
        return CGRect(x: hamper.minX, y: hamper.minY - extra, width: hamper.width, height: hamper.height + extra)
    }

    /// Where a control's drawing is, and where a tap on it lands.
    static func rect(for control: RoomControl) -> CGRect? {
        switch control {
        case .wardrobe: wardrobe
        case .nameSign: sign
        case .occasion: calendar
        case .laptop: laptop
        case .helpDrawer: drawers[0]
        case .feedbackDrawer: drawers[1]
        case .privacyDrawer: drawers[2]
        case .suitcase: suitcase
        case .hamper: hamper
        case .savedLooks: nil
        }
    }
}

/// The sideways scene scaled to the height between the top of the screen and the tab bar.
nonisolated struct SidewaysLayout: Equatable, Sendable {
    let scale: CGFloat
    /// Where scene x 0 and y 0 land.
    let origin: CGPoint
    /// The scene's size in points.
    var sceneSize: CGSize { CGSize(width: SidewaysStage.width * scale, height: SidewaysStage.height * scale) }

    /// - Parameters:
    ///   - height: the whole screen's height.
    ///   - top: the space taken at the top (the status bar, if any).
    ///   - bottom: the space the tab bar and home indicator take.
    ///   - leading: the safe area at the leading edge, where the camera housing can be.
    ///   - maximumWidth: the most of the screen's width the scene may take, so the controls fit.
    init(height: CGFloat, top: CGFloat, bottom: CGFloat, leading: CGFloat, maximumWidth: CGFloat) {
        let available = max(0, height - top - bottom)
        let heightScale = available / SidewaysStage.visibleBottom
        let widthScale = maximumWidth / SidewaysStage.width
        scale = max(0.01, min(heightScale, widthScale, 1))
        origin = CGPoint(x: leading, y: top)
    }

    func rect(_ stage: CGRect) -> CGRect {
        CGRect(
            x: origin.x + stage.minX * scale,
            y: origin.y + stage.minY * scale,
            width: stage.width * scale,
            height: stage.height * scale)
    }

    var floorY: CGFloat { origin.y + SidewaysStage.floorY * scale }
    var sceneMaxX: CGFloat { origin.x + sceneSize.width }
}
