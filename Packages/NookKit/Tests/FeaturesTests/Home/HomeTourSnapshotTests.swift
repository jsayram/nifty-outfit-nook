import DesignSystem
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Home's quick tour (Phase 16a), compared with the PNGs in `__Snapshots__/HomeTourSnapshotTests`:
/// each of the four steps over the phone's room, a step in dark, the large-text page at AX5
/// (where the card can't sit clear of the row, so it shows on its own), and the wide room on
/// the 11-inch iPad held sideways (the card beside the tall wardrobe).
///
/// The spotlight is given the same rects the room anchors the tour to (`RoomCanvas.tourSpots`),
/// so these check the drawing and the card's placement. That the anchors follow the real
/// controls on screen, through rotation and window resizes, is checked by the UI tests.
@MainActor
@Suite(.heavyMainActorWork)
struct HomeTourSnapshotTests {
    static let content = HomeSnapshotTests.demo
    /// The iPhone 17's safe area, which the tour keeps its card inside.
    static let phoneSafeArea = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)

    @Test(arguments: 0..<4)
    func phoneStep(index: Int) {
        let layout = PhoneScreen.iPhone17.layout
        assertTourSnapshot(
            RoomCanvas(layout: layout, content: Self.content, open: { _ in }),
            step: step(index, of: .phoneRoom), target: spot(index, in: layout), size: layout.size,
            safeArea: Self.phoneSafeArea, named: "phone-\(index + 1)")
    }

    @Test func phoneDark() {
        let layout = PhoneScreen.iPhone17.layout
        assertTourSnapshot(
            RoomCanvas(layout: layout, content: Self.content, open: { _ in }),
            step: step(1, of: .phoneRoom), target: spot(1, in: layout), size: layout.size,
            safeArea: Self.phoneSafeArea, colorScheme: .dark, named: "phone-dark")
    }

    /// AX5: the card is as tall as most of the screen, so it shows without a spotlight and its
    /// buttons stay in reach.
    @Test func largestTextSize() {
        let size = PhoneScreen.iPhone17.size
        let page = HomeLargeTextView(content: Self.content, open: { _ in }, notice: { EmptyView() })
            .padding(.top, 116)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.nook.wallGradient)
        // The Source row, near the top as the tour scrolls it.
        let row = CGRect(x: 16, y: 200, width: 370, height: 150)
        assertTourSnapshot(
            page, step: step(2, of: .largeText), target: row, size: size, safeArea: Self.phoneSafeArea,
            dynamicTypeSize: .accessibility5, named: "ax5")
    }

    @Test(.ipadSnapshots) func iPadLandscape() {
        let layout = IPadWindow.iPad11Landscape.roomLayout
        assertTourSnapshot(
            RoomCanvas(layout: layout, content: Self.content, open: { _ in }),
            step: step(1, of: .iPadRoom), target: spot(1, in: layout), size: layout.size,
            safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), named: "ipad-landscape")
    }

    // MARK: Helpers

    private func step(_ index: Int, of variant: HomeTour.Variant) -> NookTourStep {
        let definition = HomeTour.definition(for: variant)
        let control: RoomControl = [.laptop, .wardrobe, .suitcase, .nameSign][index]
        return NookTourStep(
            title: definition.steps[index].title, message: definition.steps[index].message, index: index,
            count: definition.steps.count, finishTitle: definition.finishTitle,
            targetLabel: control.accessibilityLabel(for: Self.content))
    }

    /// The rect the room anchors each step to: the drawn laptop, wardrobe, suitcase and sign.
    private func spot(_ index: Int, in layout: RoomLayout) -> CGRect {
        let plan = layout.plan
        return layout.rect([plan.laptop, plan.wardrobe, plan.suitcase, plan.sign][index])
    }

    private func assertTourSnapshot(
        _ screen: some View,
        step: NookTourStep,
        target: CGRect,
        size: CGSize,
        safeArea: EdgeInsets,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        scale: CGFloat = 1,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let view = ZStack(alignment: .topLeading) {
            screen.dynamicTypeSize(dynamicTypeSize)
            NookTourOverlay(
                step: step, target: target, safeArea: safeArea, onNext: {}, onBack: {}, onSkip: {}, onTarget: {}
            )
            .dynamicTypeSize(dynamicTypeSize)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .environment(\.roomIsStillImage, true)
        .environment(\.closetIsStillImage, true)
        .environment(\.nookStaticRendering, true)
        .environment(\.colorScheme, colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        let renderer = ImageRenderer(content: view.snapshotPhotos())
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        assertSnapshot(
            of: image,
            as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: scale),
            named: name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
