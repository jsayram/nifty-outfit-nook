import CoreGraphics

/// One arrangement of the room: where every drawing, plate and control sits, in stage units.
///
/// There are three (Phase 15a):
///
/// - `upright`: the phone room, `screens/home.html` on its 390-unit stage (`RoomStage`).
/// - `tall`: the room for an upright iPad, from the room in `screens/ipad-home-portrait.html`,
///   594 units wide. The furniture is about 1.15 times the phone's and spread across the wall.
/// - `wide`: the room for an iPad held sideways, from `css/home-wide.css` at 1,194 units wide.
///   Wardrobe, window, suitcase, desk, shelf and sign stand side by side across the room.
///
/// The tall and wide rooms move whole pieces of furniture, never parts of one: each group (the
/// wardrobe with its rail, flats and plate, the desk with its laptop, lamp, chair and drawers)
/// moves and grows around its top-left corner, as the mockups' CSS does with
/// `transform: scale(...)`. So a plate stays on its drawing in every arrangement.
nonisolated struct RoomPlan: Equatable, Sendable {
    nonisolated enum Kind: String, CaseIterable, Hashable, Sendable {
        case upright
        case tall
        case wide
    }

    let kind: Kind
    /// The stage's width.
    let width: CGFloat
    /// The floor line.
    let floorY: CGFloat
    /// The band of the stage that must show between the bars: from the title to just below the
    /// lowest drawing. The wall, the floor and the bed carry on past it.
    let visibleTop: CGFloat
    let visibleBottom: CGFloat
    var visibleHeight: CGFloat { visibleBottom - visibleTop }

    let title: CGRect
    let window: CGRect
    let shelfTop: CGRect
    let shelfFrames: CGRect
    let savedLooks: CGRect
    let savedPlate: CGRect
    let framedLooks: CGRect
    let frameWindows: [CGRect]
    let frameTargets: [CGRect]
    let calendar: CGRect
    let occasion: CGRect
    let wardrobe: CGRect
    let wardrobeRail: CGRect
    let wardrobeFlats: CGRect
    let closetPlate: CGRect
    let sign: CGRect
    let signName: CGRect
    let rug: CGRect
    let desk: CGRect
    let laptop: CGRect
    let laptopScreen: CGRect
    let lamp: CGRect
    let chair: CGRect
    let lampGlow: CGRect
    let drawers: [CGRect]
    /// A drawer's plate, inside its drawer.
    let drawerPlateInset: CGRect
    let maya: CGRect
    let mayaZs: CGRect
    let suitcase: CGRect
    let suitcaseArt: CGRect
    let sourcePlate: CGRect
    let scopePlate: CGRect
    let hamper: CGRect
    let hamperArt: CGRect
    let hamperFullArt: CGRect
    let laundryPlate: CGRect
    /// The bed stands in the canvas's bottom-right corner at this size, its top never above
    /// `bedTop`, so it stays clear of the desk.
    let bedSize: CGSize
    let bedTop: CGFloat

    /// How much bigger than the phone's each group is drawn. The shelf's sets the size of the
    /// looks in its frames, and Maya's the size of her z's.
    let shelfScale: CGFloat
    let mayaScale: CGFloat
    /// The pitch between drawer fronts. Below the scale that makes this 44 points, two drawers
    /// can't both have a full target.
    var drawerPitch: CGFloat { drawers[1].minY - drawers[0].minY }

    /// The smallest scale, from stage units to points, that still gives every control a 44 pt
    /// target.
    var minimumScale: CGFloat { 44 / drawerPitch }

    static func plan(_ kind: Kind) -> RoomPlan {
        switch kind {
        case .upright: upright
        case .tall: tall
        case .wide: wide
        }
    }

    /// Where a control's drawing is, before its tap area is grown to 44 x 44 points.
    func rect(for control: RoomControl) -> CGRect {
        switch control {
        case .wardrobe: wardrobe
        case .savedLooks: savedLooks
        case .nameSign: sign
        case .occasion: occasion
        case .laptop: laptopScreen
        case .helpDrawer: drawers[0]
        case .feedbackDrawer: drawers[1]
        case .privacyDrawer: drawers[2]
        case .suitcase: suitcase
        case .hamper: hamper
        }
    }

    /// Where the hamper's drawing sits. The full one is taller, for the heap above the rim.
    func hamperArt(for look: HamperLook) -> CGRect {
        look == .full ? hamperFullArt : hamperArt
    }

    // MARK: - The three rooms

    /// The phone room, exactly as `RoomStage` has it.
    static let upright = RoomPlan(
        kind: .upright, width: RoomStage.width, floorY: RoomStage.floorY,
        visibleTop: RoomStage.visibleTop, visibleBottom: RoomStage.visibleBottom,
        title: RoomStage.title, groups: .identity)

    /// The upright iPad's room (`ipad-home-portrait.html`, the room left of its old request panel).
    static let tall = RoomPlan(
        kind: .tall, width: 594, floorY: 628, visibleTop: 40, visibleBottom: 828,
        title: CGRect(x: 24, y: 46, width: 340, height: 44),
        groups: Groups(
            wardrobe: Move(to: CGPoint(x: 16, y: 174.6), scale: 1.065),
            window: Move(to: CGPoint(x: 220, y: 104), scale: 1.353),
            shelf: Move(to: CGPoint(x: 408, y: 52), scale: 1.222),
            sign: Move(to: CGPoint(x: 213, y: 328), scale: 1.307),
            calendar: Move(to: CGPoint(x: 362.5, y: 310.1), scale: 1.15),
            desk: Move(to: CGPoint(x: 352, y: 500), scale: 1.15),
            suitcase: Move(to: CGPoint(x: 26, y: 486), scale: 1.143),
            hamper: Move(to: CGPoint(x: 16, y: 708), scale: 1.15),
            maya: Move(to: CGPoint(x: 236, y: 706), scale: 1.15),
            rug: CGRect(x: 96, y: 642, width: 358.8, height: 174.8),
            bedSize: CGSize(width: 135.7, height: 312.8), bedTop: 692))

    /// The iPad room held sideways (`home-wide.css` at 1,194 x 834). Its desk stands at
    /// 58% of the width less 30 units, as the CSS has it.
    static let wide = RoomPlan(
        kind: .wide, width: 1194, floorY: 600, visibleTop: 40, visibleBottom: 758,
        title: RoomStage.title,
        groups: Groups(
            wardrobe: Move(to: CGPoint(x: 83.6, y: 168), scale: 1.2),
            window: Move(to: CGPoint(x: 417.9, y: 156), scale: 1.3),
            shelf: Move(to: CGPoint(x: 883.6, y: 88), scale: 1.3),
            sign: Move(to: CGPoint(x: 883.6, y: 355), scale: 1.3),
            calendar: Move(to: CGPoint(x: 678.5, y: 268), scale: 1.2),
            desk: Move(to: CGPoint(x: 662.5, y: 466), scale: 1.2),
            suitcase: Move(to: CGPoint(x: 358.2, y: 440), scale: 1.2),
            hamper: Move(to: CGPoint(x: 119.4, y: 636), scale: 1.1),
            maya: Move(to: CGPoint(x: 573.1, y: 685), scale: 1),
            rug: CGRect(x: 394, y: 596, width: 420, height: 160),
            bedSize: CGSize(width: 156, height: 360), bedTop: 398))
}

// MARK: - Building a plan from the phone room

nonisolated extension RoomPlan {
    /// Where one group's top-left corner goes, and how much it grows around that corner.
    nonisolated struct Move: Equatable, Sendable {
        let to: CGPoint?
        let scale: CGFloat

        static let none = Move(to: nil, scale: 1)

        /// `rect`, a part of the group whose top-left corner is `anchor` in the phone room.
        func apply(_ rect: CGRect, anchor: CGPoint) -> CGRect {
            let origin = to ?? anchor
            return CGRect(
                x: origin.x + (rect.minX - anchor.x) * scale,
                y: origin.y + (rect.minY - anchor.y) * scale,
                width: rect.width * scale,
                height: rect.height * scale)
        }
    }

    /// Every group's move, plus the two things the mockups size on their own: the rug and the bed.
    nonisolated struct Groups: Equatable, Sendable {
        var wardrobe = Move.none
        var window = Move.none
        var shelf = Move.none
        var sign = Move.none
        var calendar = Move.none
        var desk = Move.none
        var suitcase = Move.none
        var hamper = Move.none
        var maya = Move.none
        var rug = RoomStage.rug
        var bedSize = RoomStage.bedSize
        var bedTop = RoomStage.bedTop

        static let identity = Groups()
    }

    private init(
        kind: Kind, width: CGFloat, floorY: CGFloat, visibleTop: CGFloat, visibleBottom: CGFloat, title: CGRect,
        groups: Groups
    ) {
        typealias S = RoomStage
        self.kind = kind
        self.width = width
        self.floorY = floorY
        self.visibleTop = visibleTop
        self.visibleBottom = visibleBottom
        self.title = title

        let wardrobe = { (rect: CGRect) in groups.wardrobe.apply(rect, anchor: S.wardrobe.origin) }
        self.wardrobe = wardrobe(S.wardrobe)
        wardrobeRail = wardrobe(S.wardrobeRail)
        wardrobeFlats = wardrobe(S.wardrobeFlats)
        closetPlate = wardrobe(S.closetPlate)

        window = groups.window.apply(S.window, anchor: S.window.origin)

        let shelf = { (rect: CGRect) in groups.shelf.apply(rect, anchor: S.shelfTop.origin) }
        shelfTop = shelf(S.shelfTop)
        shelfFrames = shelf(S.shelfFrames)
        savedLooks = shelf(S.savedLooks)
        savedPlate = shelf(S.savedPlate)
        framedLooks = shelf(S.framedLooks)
        frameWindows = S.frameWindows.map(shelf)
        frameTargets = S.frameTargets.map(shelf)
        shelfScale = groups.shelf.scale

        let sign = { (rect: CGRect) in groups.sign.apply(rect, anchor: S.sign.origin) }
        self.sign = sign(S.sign)
        signName = sign(S.signName)

        let calendar = { (rect: CGRect) in groups.calendar.apply(rect, anchor: S.calendar.origin) }
        self.calendar = calendar(S.calendar)
        occasion = calendar(S.occasion)

        let desk = { (rect: CGRect) in groups.desk.apply(rect, anchor: S.desk.origin) }
        self.desk = desk(S.desk)
        laptop = desk(S.laptop)
        laptopScreen = desk(S.laptopScreen)
        lamp = desk(S.lamp)
        chair = desk(S.chair)
        lampGlow = desk(S.lampGlow)
        drawers = S.drawers.map(desk)
        let insetScale = groups.desk.scale
        drawerPlateInset = CGRect(
            x: S.drawerPlateInset.minX * insetScale, y: S.drawerPlateInset.minY * insetScale,
            width: S.drawerPlateInset.width * insetScale, height: S.drawerPlateInset.height * insetScale)

        let suitcase = { (rect: CGRect) in groups.suitcase.apply(rect, anchor: S.suitcase.origin) }
        self.suitcase = suitcase(S.suitcase)
        suitcaseArt = suitcase(S.suitcaseArt)
        sourcePlate = suitcase(S.sourcePlate)
        scopePlate = suitcase(S.scopePlate)

        let hamper = { (rect: CGRect) in groups.hamper.apply(rect, anchor: S.hamper.origin) }
        self.hamper = hamper(S.hamper)
        hamperArt = hamper(S.hamperArt)
        hamperFullArt = hamper(S.hamperFullArt)
        laundryPlate = hamper(S.laundryPlate)

        let maya = { (rect: CGRect) in groups.maya.apply(rect, anchor: S.maya.origin) }
        self.maya = maya(S.maya)
        mayaZs = maya(S.mayaZs)
        mayaScale = groups.maya.scale

        rug = groups.rug
        bedSize = groups.bedSize
        bedTop = groups.bedTop
    }
}
