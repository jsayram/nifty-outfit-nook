import CoreGraphics
import SwiftUI
import Testing

@testable import Features

/// The iPad rooms (Phase 15a): each window gets the right arrangement, every control keeps a
/// real target, and the plates stay on their furniture.
struct RoomPlanTests {
    /// The phone room built through `RoomPlan` is exactly `RoomStage`, so phones don't change.
    @Test func uprightPlanIsThePhoneRoom() {
        let plan = RoomPlan.upright
        #expect(plan.width == RoomStage.width)
        #expect(plan.wardrobe == RoomStage.wardrobe)
        #expect(plan.drawers == RoomStage.drawers)
        #expect(plan.frameTargets == RoomStage.frameTargets)
        #expect(plan.drawerPlateInset == RoomStage.drawerPlateInset)
        #expect(plan.minimumScale == RoomLayout.minimumScale)
        for control in RoomControl.allCases {
            #expect(plan.rect(for: control) == control.stageRect)
        }
    }

    @Test(arguments: IPadWindow.full)
    func eachIPadGetsTheRoomForItsShape(window: IPadWindow) {
        let layout = window.roomLayout
        #expect(layout.plan.kind == window.expectedRoom, "\(window) got \(layout.plan.kind)")
        #expect(!layout.scrolls, "The room scrolls on \(window)")
    }

    @Test(arguments: IPadWindow.allCases)
    func everyControlIsAtLeast44Points(window: IPadWindow) {
        let layout = window.roomLayout
        for control in RoomControl.allCases {
            let target = layout.target(for: control)
            #expect(target.width >= 44 && target.height >= 44, "\(control) on \(window) is \(target.size)")
        }
        #expect(layout.scale >= layout.plan.minimumScale - 0.001 || layout.plan.kind == .upright)
    }

    /// Neighbouring controls don't steal each other's taps. As on the phone, the wardrobe is
    /// the exception: the suitcase stands in front of it.
    @Test(arguments: IPadWindow.allCases)
    func controlsDoNotOverlap(window: IPadWindow) {
        let layout = window.roomLayout
        let controls = RoomControl.allCases.filter { $0 != .wardrobe }
        for (index, first) in controls.enumerated() {
            for second in controls.dropFirst(index + 1) {
                let overlap = layout.target(for: first).intersection(layout.target(for: second))
                #expect(
                    overlap.isNull || overlap.width < 0.5 || overlap.height < 0.5,
                    "\(first) and \(second) overlap by \(overlap.size) on \(window)")
            }
        }
    }

    /// Every control is inside the window and between the bars.
    @Test(arguments: IPadWindow.allCases)
    func everyControlIsBetweenTheBars(window: IPadWindow) {
        let layout = window.roomLayout
        for control in RoomControl.allCases {
            let target = layout.target(for: control)
            #expect(target.minY >= layout.insets.top - 0.5, "\(control) is under the navigation bar on \(window)")
            #expect(
                target.maxY <= layout.contentHeight - layout.insets.bottom + 0.5,
                "\(control) is under the tab bar on \(window)")
            #expect(target.minX >= -0.5 && target.maxX <= layout.size.width + 0.5, "\(control) is off \(window)")
        }
    }

    /// The plates are part of their furniture's group, so each one stays on its drawing.
    @Test(arguments: RoomPlan.Kind.allCases)
    func platesStayOnTheirFurniture(kind: RoomPlan.Kind) {
        let plan = RoomPlan.plan(kind)
        #expect(plan.wardrobe.contains(plan.closetPlate))
        #expect(plan.wardrobe.contains(plan.wardrobeRail))
        #expect(plan.suitcaseArt.contains(plan.sourcePlate.insetBy(dx: 1, dy: 1)))
        #expect(plan.suitcaseArt.contains(plan.scopePlate.insetBy(dx: 1, dy: 1)))
        #expect(plan.hamperArt.contains(plan.laundryPlate))
        #expect(plan.sign.contains(plan.signName))
        #expect(plan.calendar.contains(plan.occasion))
        #expect(plan.laptop.contains(plan.laptopScreen))
        for drawer in plan.drawers {
            #expect(plan.desk.contains(drawer))
        }
        #expect(plan.shelfFrames.contains(plan.framedLooks.insetBy(dx: 1, dy: 4)))
        #expect(plan.hamperFullArt.maxY == plan.hamperArt.maxY)
    }

    /// The title doesn't run into the window or the shelf, in any arrangement.
    @Test(arguments: RoomPlan.Kind.allCases)
    func titleIsClearOfTheWall(kind: RoomPlan.Kind) {
        let plan = RoomPlan.plan(kind)
        // The phone title shrinks to fit beside the plant (it's allowed to run into the
        // plant's leaves, as in `home.html`), so only the iPad rooms are checked.
        guard kind != .upright else { return }
        #expect(!plan.title.intersects(plan.window), "\(kind)")
        #expect(!plan.title.intersects(plan.shelfTop), "\(kind)")
        #expect(!plan.title.intersects(plan.wardrobe), "\(kind)")
    }

    /// The wide room stands its furniture side by side: wardrobe, suitcase, desk, then the
    /// shelf and sign, as `home-wide.css` does.
    @Test func wideRoomRunsAcrossTheWall() {
        let plan = RoomPlan.wide
        #expect(plan.wardrobe.maxX <= plan.suitcase.minX)
        #expect(plan.suitcase.maxX <= plan.desk.minX)
        #expect(plan.desk.maxX <= plan.sign.minX + 30)
        #expect(plan.shelfTop.minX == plan.sign.minX)
    }

    /// A tall, narrow window that's still regular width doesn't get a room it can't fit.
    @Test func awkwardWindowFallsBackToThePhoneRoom() {
        let layout = WindowLayout.room(
            size: CGSize(width: 520, height: 600), insets: IPadWindow.bars, horizontalSizeClass: .regular)
        #expect(layout.plan.kind == .upright)
    }

    @Test func compactWidthAlwaysGetsThePhoneRoom() {
        for size in [CGSize(width: 1210, height: 834), CGSize(width: 416, height: 1210)] {
            let layout = WindowLayout.room(size: size, insets: IPadWindow.bars, horizontalSizeClass: .compact)
            #expect(layout.plan.kind == .upright)
        }
    }

    /// When there's more height than the room needs, it sits in the middle of the space between
    /// the bars rather than against the top.
    @Test func roomSitsInTheMiddleOfSpareHeight() {
        let layout = IPadWindow.iPad13Landscape.roomLayout
        let plan = layout.plan
        let top = layout.originY + plan.visibleTop * layout.scale - layout.insets.top
        let bottom = layout.size.height - layout.insets.bottom - (layout.originY + plan.visibleBottom * layout.scale)
        #expect(abs(top - bottom) < 0.5)
    }
}

/// iPad windows, with the bar heights measured on the iOS 26.5 simulator (iPad Pro 11-inch):
/// 86 points at the top and 77 for the bottom tab bar, in both orientations.
enum IPadWindow: String, CaseIterable, CustomTestStringConvertible {
    case iPad11Portrait
    case iPad11Landscape
    case iPad13Portrait
    case iPad13Landscape
    case iPadMiniPortrait
    case iPadMiniLandscape
    /// Split View and Stage Manager sizes that are still regular width.
    case iPad11LandscapeTwoThirds
    case iPad13LandscapeHalf

    static let bars = EdgeInsets(top: 86, leading: 0, bottom: 77, trailing: 0)

    /// Full-screen windows.
    static let full: [IPadWindow] = [
        .iPad11Portrait, .iPad11Landscape, .iPad13Portrait, .iPad13Landscape, .iPadMiniPortrait, .iPadMiniLandscape,
    ]

    var size: CGSize {
        switch self {
        case .iPad11Portrait: CGSize(width: 834, height: 1210)
        case .iPad11Landscape: CGSize(width: 1210, height: 834)
        case .iPad13Portrait: CGSize(width: 1032, height: 1376)
        case .iPad13Landscape: CGSize(width: 1376, height: 1032)
        case .iPadMiniPortrait: CGSize(width: 744, height: 1133)
        case .iPadMiniLandscape: CGSize(width: 1133, height: 744)
        case .iPad11LandscapeTwoThirds: CGSize(width: 795, height: 834)
        case .iPad13LandscapeHalf: CGSize(width: 688, height: 1032)
        }
    }

    var expectedRoom: RoomPlan.Kind {
        size.width > size.height ? .wide : .tall
    }

    var roomLayout: RoomLayout {
        WindowLayout.room(size: size, insets: Self.bars, horizontalSizeClass: .regular)
    }

    var testDescription: String { rawValue }
}
