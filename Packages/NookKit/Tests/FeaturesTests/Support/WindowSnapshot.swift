import DesignSystem
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// The iPad windows the Phase 15b snapshots are drawn in: the 11-inch iPad both ways, and a
/// window a third of its width held sideways, which is compact, so it gets the phone layouts.
enum SnapshotWindow: String, CaseIterable {
    case landscape
    case portrait
    case narrow

    var size: CGSize {
        switch self {
        case .landscape: IPadWindow.iPad11Landscape.size
        case .portrait: IPadWindow.iPad11Portrait.size
        // Measured on the iOS 26.5 simulator (docs/ipad.md).
        case .narrow: CGSize(width: 416, height: 834)
        }
    }

    var sizeClass: UserInterfaceSizeClass {
        self == .narrow ? .compact : .regular
    }
}

/// What a still page shows below its content, where on screen it would scroll: the wall for
/// pages on the wall, the floor for pages on the floor.
enum SnapshotBackdrop {
    case wall
    case floor
}

/// Draws `view` as one window of `window`'s size and width class, from its top as if not
/// scrolled, without the system bars, at 1x like the other iPad snapshots (`docs/ipad.md`), and
/// compares it with the PNG in the calling suite's `__Snapshots__` folder.
@MainActor
func assertWindowSnapshot(
    _ view: some View,
    in window: SnapshotWindow,
    backdrop: SnapshotBackdrop = .wall,
    colorScheme: ColorScheme = .light,
    dynamicTypeSize: DynamicTypeSize = .large,
    named name: String,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let size = window.size
    let content =
        view
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .background {
            switch backdrop {
            case .wall: Color.nook.wallGradient
            case .floor: Color.nook.floor
            }
        }
        .environment(\.horizontalSizeClass, window.sizeClass)
        .environment(\.scenePhase, .active)
        .environment(\.closetIsStillImage, true)
        .environment(\.roomIsStillImage, true)
        .environment(\.nookStaticRendering, true)
        .environment(\.colorScheme, colorScheme)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.locale, ClosetTestTime.locale)
        .environment(\.calendar, ClosetTestTime.calendar)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(size)
    guard let image = renderer.uiImage else {
        Issue.record("ImageRenderer produced no image for \(name)")
        return
    }
    SnapshotTesting.assertSnapshot(
        of: image,
        as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: 1),
        named: name,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
}
