import CoreGraphics
import Models
import SwiftUI
import Testing

@testable import Features

/// Which layout Home picks, and the sizes the large-text and sideways layouts rely on (Phase 5b).
struct HomeLayoutTests {
    @Test(arguments: DynamicTypeSize.allCases)
    func accessibilitySizesGetTheLargeTextLayoutInEveryOrientation(size: DynamicTypeSize) {
        for sizeClass in [UserInterfaceSizeClass.regular, .compact, nil] {
            let layout = HomeLayout(dynamicTypeSize: size, verticalSizeClass: sizeClass)
            #expect((layout == .largeText) == size.isAccessibilitySize, "\(size), \(String(describing: sizeClass))")
        }
    }

    @Test func aPhoneHeldSidewaysGetsTheSidewaysRoom() {
        #expect(HomeLayout(dynamicTypeSize: .large, verticalSizeClass: .compact) == .sideways)
        #expect(HomeLayout(dynamicTypeSize: .xxxLarge, verticalSizeClass: .compact) == .sideways)
        #expect(HomeLayout(dynamicTypeSize: .large, verticalSizeClass: .regular) == .room)
        #expect(HomeLayout(dynamicTypeSize: .xxxLarge, verticalSizeClass: .regular) == .room)
    }

    /// Rows and tiles say what's written on them, so Voice Control matches what she sees.
    @Test func rowLabelsUseTheWordsOnScreen() {
        let content = HomeRoomContent(
            signName: "Lily", source: SourcePlate(kind: .suitcase(name: "Weekend"), pieceCount: 8), hamper: .off)
        #expect(RoomControl.suitcase.rowLabel(for: content) == "Source: Weekend, 8 pieces, Suitcase only")
        #expect(RoomControl.hamper.rowLabel(for: content) == "Laundry: Off")
        #expect(RoomControl.hamper.rowLabel(for: HomeRoomContent()) == "Laundry")
        #expect(RoomControl.laptop.rowLabel(for: content) == "Style Me")
        #expect(RoomControl.occasion.rowLabel(for: content) == "Occasion")
        #expect(RoomControl.helpDrawer.rowLabel(for: content) == "Help")
        #expect(RoomControl.feedbackDrawer.rowLabel(for: content) == "Send feedback")
        #expect(RoomControl.privacyDrawer.rowLabel(for: content) == "Privacy and terms")
        #expect(RoomControl.nameSign.rowLabel(for: content) == "Name sign: Lily")
    }

    /// The banner's rail sits where it does on the room's wardrobe, and its right end shows
    /// inside the wardrobe's visible edge.
    @MainActor @Test func bannerRailShowsInsideTheWardrobeEdge() {
        let rail = HomeBanner.rail
        #expect(rail.maxX > HomeBanner.wardrobeEdge.width / 2)
        #expect(rail.minY > 0 && rail.maxY < HomeBanner.height)
    }

    // MARK: - Sideways

    static let iPhone17 = SidewaysLayout(height: 402, top: 0, bottom: 64, leading: 62, maximumWidth: 874 - 124 - 340)

    /// The scene keeps its proportions and fits above the tab bar.
    @Test func sidewaysSceneFitsAboveTheTabBar() {
        let layout = Self.iPhone17
        #expect(layout.origin.y + SidewaysStage.visibleBottom * layout.scale <= 402 - 64 + 0.5)
        #expect(layout.sceneMaxX <= 874 - 62 - 340 + 0.5, "The controls column keeps its width")
        #expect(layout.scale > 0.85, "The scene shouldn't shrink much on an iPhone 17: \(layout.scale)")
    }

    /// The SE is narrower: the scene gives way to the controls, never the other way round.
    @Test func sidewaysSceneGivesWayOnASmallPhone() {
        let layout = SidewaysLayout(height: 375, top: 0, bottom: 53, leading: 0, maximumWidth: 667 - 340)
        #expect(layout.sceneMaxX <= 667 - 340 + 0.5)
        #expect(layout.origin.y + SidewaysStage.visibleBottom * layout.scale <= 375 - 53 + 0.5)
    }

    /// Every drawing that does something is inside the scene, and every room control but the
    /// shelf has one (Saved Looks is the tab).
    @Test func everySidewaysControlIsInTheScene() {
        let scene = CGRect(x: 0, y: 0, width: SidewaysStage.width, height: SidewaysStage.visibleBottom)
        for control in RoomControl.allCases {
            guard let rect = SidewaysStage.rect(for: control) else {
                #expect(control == .savedLooks)
                continue
            }
            #expect(scene.contains(rect), "\(control) is outside the scene: \(rect)")
        }
    }

    @Test func fullHamperReachesHigherSideways() {
        let full = SidewaysStage.hamperArt(.full)
        let empty = SidewaysStage.hamperArt(.empty)
        #expect(full.maxY == empty.maxY)
        #expect(full.minY < empty.minY)
    }
}
